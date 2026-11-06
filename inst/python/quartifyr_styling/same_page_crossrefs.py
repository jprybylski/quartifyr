"""Resolves ``crossref-hyperlinks: "same-page"`` markers into a final
hyperlinked/not decision, using headless LibreOffice purely as a
*read-only* pagination oracle -- it never writes the docx.

Background: ``layout.py``'s ``apply_layout()`` runs on the pass-1 shell,
before reportifyr has filled in real figures/tables/text, so real page
numbers don't exist yet there. When ``crossref-hyperlinks: "same-page"``
is set, ``apply_layout()`` doesn't try to resolve anything -- it just
drops a small bookmark (``quartifyr-crossref-target-N``) immediately
before each crossref's ``REF`` field, marking it for later resolution, and
leaves the field hyperlinked (the same as mode ``true``) as the safe
fallback if this module never runs.

This module is that later step: run it on the *filled* docx (``report/
draft/*.docx`` / ``report/final/*.docx``, after ``reportifyr::
build_report()``/``finalize_document()``, analogous to and typically run
alongside ``recalculate_fields.py``). For each marker, it needs to know
two real page numbers -- where the crossref itself sits, and where its
target bookmark sits -- and that requires an actual layout engine.

An earlier version of ``crossref-hyperlinks: "same-page"`` tried to avoid
needing this step at all, by emitting a live nested Word field (``IF
{PAGE} = {PAGEREF bookmark} ...``) that Word/LibreOffice would resolve on
its own whenever the document gets paginated. Abandoned after confirming,
via a real headless-LibreOffice round-trip, that it silently mangles the
nested field into garbage instead of evaluating it -- see ``layout.py``'s
module docstring. This module sidesteps that entirely: LibreOffice is
asked only to report page numbers (``ViewCursor.getPage()`` against each
bookmark's anchor) via a small Basic macro, never to save/re-serialize the
docx -- so LibreOffice's own OOXML round-tripping (already demonstrated
fragile for complex fields) never gets a chance to touch the file. Every
actual edit to the document -- stripping ``\\h`` where the reference and
target share a page, removing the now-unneeded markers -- happens in
plain python-docx/lxml, the same well-tested path ``layout.py`` already
uses.

EXPERIMENTAL, sharing ``recalculate_fields.py``'s headless-LibreOffice
launcher (``_soffice.py``): the same profile warm-up that fixed the macOS
hang, the same heartbeat check that reports a macro that never starts as
unavailable after 30 seconds, and the same tree kill on timeout. This module
drives the identical ``soffice --headless ... macro:///...`` mechanism with a
different macro. Verified on macOS (a real document, repeated and concurrent
runs); Windows and Linux were not re-tested.
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from xml.sax.saxutils import escape as _xml_escape

import docx
from docx.oxml.ns import qn

from ._ooxml_fields import SAME_PAGE_MARKER_PREFIX, match_ref_field_run_group, strip_hyperlink_switch
from ._soffice import (
    SofficeError,
    SofficeNotFoundError,
    SofficeTimeoutError,
    SofficeUnavailableError,
    resolve_soffice,
    rmtree_retrying,
    run_macro,
    started_marker_basic,
    warm_up_profile,
)

_MACRO_XBA_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">
<script:module xmlns:script="http://openoffice.org/2000/script" script:name="Module1" script:language="StarBasic" script:moduleType="normal">Sub ReadPages{started}
    Dim oDoc As Object
    oDoc = ThisComponent

    Dim oBookmarks As Object
    oBookmarks = oDoc.Bookmarks

    Dim oVC As Object
    oVC = oDoc.CurrentController.ViewCursor

    Dim iIn As Integer, iOut As Integer
    Dim sLine As String, sMarker As String, sTarget As String
    Dim aParts() As String
    Dim nMarkerPage As Integer, nTargetPage As Integer

    iIn = FreeFile
    Open &quot;{pairs_path}&quot; For Input As #iIn
    iOut = FreeFile
    Open &quot;{results_path}&quot; For Output As #iOut

    Do While Not EOF(iIn)
        Line Input #iIn, sLine
        If Len(Trim(sLine)) > 0 Then
            aParts = Split(sLine, Chr(9))
            sMarker = aParts(0)
            sTarget = aParts(1)
            If oBookmarks.hasByName(sMarker) And oBookmarks.hasByName(sTarget) Then
                oVC.gotoRange(oBookmarks.getByName(sMarker).Anchor, False)
                nMarkerPage = oVC.getPage()
                oVC.gotoRange(oBookmarks.getByName(sTarget).Anchor, False)
                nTargetPage = oVC.getPage()
                Print #iOut, sMarker &amp; Chr(9) &amp; sTarget &amp; Chr(9) &amp; nMarkerPage &amp; Chr(9) &amp; nTargetPage
            End If
        End If
    Loop

    Close #iIn
    Close #iOut

    oDoc.close(False)

    Dim oDesktop As Object
    oDesktop = createUnoService(&quot;com.sun.star.frame.Desktop&quot;)
    oDesktop.terminate()
End Sub
</script:module>
"""

_SCRIPT_XLB = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">
<library:library xmlns:library="http://openoffice.org/2000/library" library:name="Standard" library:readonly="false" library:passwordprotected="false">
 <library:element library:name="Module1"/>
</library:library>
"""

_SCRIPT_XLC = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "libraries.dtd">
<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">
 <library:library library:name="Standard" xlink:href="$(USER)/basic/Standard/script.xlb/" xlink:type="simple" library:link="false"/>
</library:libraries>
"""


class SamePageCrossrefError(RuntimeError):
    """Raised when resolving ``crossref-hyperlinks: "same-page"`` markers fails."""


def _find_markers(document) -> list[tuple[str, str, object, object, object]]:
    """Returns, for every same-page marker immediately preceding a ``REF``
    field: ``(marker_name, target_bookmark, instr_text_element,
    bookmark_start_element, bookmark_end_element)``.
    """
    results = []
    for p in document.element.body.iter(qn("w:p")):
        children = list(p)
        for idx, el in enumerate(children):
            if el.tag != qn("w:bookmarkStart"):
                continue
            name = el.get(qn("w:name")) or ""
            if not name.startswith(SAME_PAGE_MARKER_PREFIX):
                continue
            # Inserted as bookmarkStart, bookmarkEnd, then the field's own
            # runs, in that order (see layout.py's
            # _mark_crossrefs_for_same_page_resolution) -- children[idx+1]
            # is guaranteed to be the matching bookmarkEnd.
            bookmark_end = children[idx + 1] if idx + 1 < len(children) else None
            following_runs = [c for c in children[idx:] if c.tag == qn("w:r")]
            found = match_ref_field_run_group(following_runs, 0)
            if found is None or bookmark_end is None:
                continue
            target_bookmark, _cached_text = found
            instr_text = following_runs[1].find(qn("w:instrText"))
            results.append((name, target_bookmark, instr_text, el, bookmark_end))
    return results


def _remove_markers(markers: list[tuple[str, str, object, object, object]]) -> None:
    for _marker, _target, _instr, bookmark_start, bookmark_end in markers:
        for el in (bookmark_start, bookmark_end):
            parent = el.getparent()
            if parent is not None:
                parent.remove(el)


def _seed_profile(
    profile_dir: Path, *, pairs_path: Path, results_path: Path, started_path: Path | None = None
) -> None:
    standard_dir = profile_dir / "user" / "basic" / "Standard"
    standard_dir.mkdir(parents=True, exist_ok=True)
    macro = _MACRO_XBA_TEMPLATE.format(
        pairs_path=_xml_escape(str(pairs_path)),
        results_path=_xml_escape(str(results_path)),
        started=started_marker_basic(started_path),
    )
    (standard_dir / "Module1.xba").write_text(macro, encoding="utf-8")
    (standard_dir / "script.xlb").write_text(_SCRIPT_XLB, encoding="utf-8")
    (profile_dir / "user" / "basic" / "script.xlc").write_text(_SCRIPT_XLC, encoding="utf-8")


def resolve_same_page_crossrefs(
    docx_path: str | Path,
    *,
    soffice_bin: str | None = None,
    timeout_seconds: int = 120,
) -> Path:
    """Resolves every ``crossref-hyperlinks: "same-page"`` marker in
    ``docx_path`` (modified in place) and returns that same path.

    Run this on the *filled* docx, after reportifyr's pass 2 -- see the
    module docstring. A no-op (skips LibreOffice entirely) if the document
    has no same-page markers at all.
    """
    docx_path = Path(docx_path).resolve()
    if not docx_path.exists():
        raise FileNotFoundError(f"docx not found: {docx_path}")

    document = docx.Document(str(docx_path))
    markers = _find_markers(document)
    if not markers:
        return docx_path

    try:
        soffice = resolve_soffice(soffice_bin)
    except SofficeNotFoundError as exc:
        raise SamePageCrossrefError(str(exc)) from None

    # mkdtemp + rmtree_retrying rather than TemporaryDirectory: see
    # recalculate_fields.py for why a Windows LibreOffice that outlives its
    # kill must not turn a timeout into a cleanup crash.
    tmp = tempfile.mkdtemp(prefix="quartifyr-same-page-")
    try:
        tmp_dir = Path(tmp)
        pairs_path = tmp_dir / "pairs.txt"
        results_path = tmp_dir / "results.txt"
        pairs_path.write_text(
            "".join(f"{marker}\t{target}\n" for marker, target, *_rest in markers),
            encoding="utf-8",
        )

        profile_dir = tmp_dir / "profile"
        started_path = tmp_dir / "macro-started"
        # See recalculate_fields.py: the profile is initialised before the
        # macro goes in, because a pre-seeded fresh profile hangs on macOS.
        warm_up_profile(soffice, profile_dir, stderr_path=tmp_dir / "soffice-warmup.log")
        _seed_profile(profile_dir, pairs_path=pairs_path, results_path=results_path, started_path=started_path)

        try:
            returncode, stderr_text = run_macro(
                soffice,
                docx_path,
                "macro:///Standard.Module1.ReadPages",
                profile_dir=profile_dir,
                stderr_path=tmp_dir / "soffice-stderr.log",
                timeout_seconds=timeout_seconds,
                started_path=started_path,
            )
        except SofficeUnavailableError as exc:
            raise SamePageCrossrefError(str(exc)) from None
        except SofficeTimeoutError:
            raise SamePageCrossrefError(
                f"LibreOffice did not finish within {timeout_seconds}s reading page numbers for "
                f"{docx_path} and was force-killed. This drives the same headless-LibreOffice "
                "mechanism as quartifyr-styling recalculate-fields -- see this module's docstring "
                "and the repo-root README.md's 'Status and known limitations' section."
            ) from None
        except SofficeError as exc:
            raise SamePageCrossrefError(str(exc)) from None

        if returncode != 0:
            raise SamePageCrossrefError(f"LibreOffice page-number lookup failed (exit {returncode}):\n{stderr_text}")

        if not results_path.exists():
            raise SamePageCrossrefError(
                f"LibreOffice exited successfully but produced no page-number results for {docx_path} -- "
                "the macro did not actually run, or errored internally without a nonzero exit code."
            )

        pages: dict[str, tuple[int, int]] = {}
        for line in results_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            marker, _target, marker_page, target_page = line.split("\t")
            pages[marker] = (int(marker_page), int(target_page))
    finally:
        rmtree_retrying(tmp)

    # Markers LibreOffice couldn't resolve (bookmark lookup failed for that
    # pair) are left as-is -- still hyperlinked, the same safe fallback as
    # if this step had never run at all.
    for marker, _target, instr_text, _start, _end in markers:
        if marker not in pages:
            continue
        marker_page, target_page = pages[marker]
        if marker_page == target_page:
            strip_hyperlink_switch(instr_text)

    _remove_markers(markers)
    document.save(str(docx_path))
    return docx_path
