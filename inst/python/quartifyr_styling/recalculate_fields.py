"""Headless Word field recalculation (ToC page numbers, etc.) via LibreOffice.

Quarto/pandoc-generated docx files contain native Word field codes (TOC,
SEQ, REF) that don't self-populate -- they show placeholder text like
"Right-click to update field" until an application actually recalculates
them. This module drives LibreOffice headlessly to do that recalculation,
so a delivered docx doesn't need a manual "select all, F9" step in Word.

Known limitation, confirmed via real end-to-end testing (not something
quartifyr can fix from the outside): LibreOffice only recognizes the main
document ToC as an updatable "index" object
(``ThisComponent.getDocumentIndexes()``). ``quarto-plus``'s List of
Figures/List of Tables (a ``TOC \\c "Figure"``/``\\c "Table"`` field
variant) aren't recognized as indexes at all, and LibreOffice hangs
indefinitely when asked to enumerate/refresh *general* text fields
(``getTextFields()``) on documents that contain them -- reproduced
consistently across multiple field-touching approaches. Figure/table
caption *numbers* aren't actually at risk from this gap: ``quarto-plus``'s
caption shortcodes compute and embed those at Quarto-render time, the SEQ
field is just a live-editable wrapper around an already-correct value.
What *is* left stale is the List of Figures/List of Tables bodies and any
plain ``REF``-style cross-reference (e.g. this project's
``appendix_crossref`` shortcode) -- those still need a one-time manual
update in Microsoft Word (Ctrl+A, then F9) after delivery.

EXPERIMENTAL / UNRELIABLE (as of this writing): the underlying ``soffice
--headless ... macro:///...`` invocation has three distinct observed
failure modes across repeated real-world runs -- (1) hangs indefinitely
(reproduced in a sandboxed environment *and* a plain native macOS
terminal, ruling out sandboxing as the cause), (2) exits cleanly within
seconds without the macro having actually run at all (file untouched), and
(3) works correctly end-to-end, ToC actually recalculated. All three were
observed against the *same* document across different runs, so this isn't
document-specific either. This module now defends against (1) by killing
the whole process group on timeout (not just the tracked PID, which can
leave an orphaned ``soffice.bin`` worker behind) and against (2) by
verifying the ToC placeholder actually disappeared rather than trusting
the exit code -- but the underlying non-determinism itself is unresolved
and looks like a real LibreOffice/macOS interaction bug outside
quartifyr's control. Treat this feature as experimental until proven
reliable in your own environment; it fails loudly and cleanly either way
(no silent false "success").
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

_MACRO_XBA = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">
<script:module xmlns:script="http://openoffice.org/2000/script" script:name="Module1" script:language="StarBasic" script:moduleType="normal">Sub UpdateAndSave
    Dim oDoc As Object
    oDoc = ThisComponent

    oDoc.updateLinks()

    Dim oIndexes As Object
    oIndexes = oDoc.getDocumentIndexes()
    Dim i As Integer
    For i = 0 To oIndexes.Count - 1
        oIndexes.getByIndex(i).update()
    Next i

    Dim oArgs(0) As New com.sun.star.beans.PropertyValue
    oArgs(0).Name = &quot;FilterName&quot;
    oArgs(0).Value = &quot;MS Word 2007 XML&quot;
    oDoc.storeToURL(oDoc.getURL(), oArgs())

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


class FieldRecalculationError(RuntimeError):
    """Raised when the headless LibreOffice recalculation step fails."""


def _seed_profile(profile_dir: Path) -> None:
    standard_dir = profile_dir / "user" / "basic" / "Standard"
    standard_dir.mkdir(parents=True, exist_ok=True)
    (standard_dir / "Module1.xba").write_text(_MACRO_XBA, encoding="utf-8")
    (standard_dir / "script.xlb").write_text(_SCRIPT_XLB, encoding="utf-8")
    (profile_dir / "user" / "basic" / "script.xlc").write_text(_SCRIPT_XLC, encoding="utf-8")


def _kill_process_tree(proc: subprocess.Popen) -> None:
    """Kill proc's entire process group, not just the single tracked PID.

    soffice's launcher can spawn a detached soffice.bin worker; a plain
    proc.kill() only signals the PID Python is tracking and can leave that
    worker running as an orphan. Reproduced: a real-world run left soffice
    alive and unkillable via the ordinary timeout path for several minutes.
    start_new_session=True (set where this process is started) puts the
    whole tree in its own process group so os.killpg reaches all of it.
    """
    try:
        pgid = os.getpgid(proc.pid)
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def recalculate_fields(
    docx_path: str | Path,
    *,
    soffice_bin: str = "soffice",
    timeout_seconds: int = 120,
) -> Path:
    """Recalculate ``docx_path``'s Word ToC (page numbers, entries) in place via LibreOffice.

    Modifies the file at ``docx_path`` and returns that same path. See the
    module docstring for what this does and does not cover.
    """
    docx_path = Path(docx_path).resolve()
    if not docx_path.exists():
        raise FileNotFoundError(f"docx not found: {docx_path}")
    if shutil.which(soffice_bin) is None:
        raise FieldRecalculationError(
            f"'{soffice_bin}' not found on PATH -- install LibreOffice "
            "(e.g. `brew install --cask libreoffice`)"
        )

    # A fresh, isolated profile per call avoids the single-instance-per-
    # profile lock LibreOffice otherwise takes, so concurrent invocations
    # (e.g. rendering several reports in parallel) don't collide.
    with tempfile.TemporaryDirectory(prefix="quartifyr-lo-profile-") as tmp:
        profile_dir = Path(tmp)
        _seed_profile(profile_dir)

        # NOTE: deliberately NOT using subprocess.run(capture_output=True).
        # soffice's --headless launcher forks a detached soffice.bin worker
        # that inherits stdout/stderr; when those are pipes (what
        # capture_output/PIPE creates), Popen.communicate() blocks forever
        # waiting for the pipe's write end to close, which it never does --
        # even after the process we actually care about has finished and
        # written the file. Redirecting to real files (not pipes) avoids
        # that deadlock entirely. Reproduced consistently: this hung every
        # time under subprocess.run(capture_output=True), every time it
        # succeeded when output went straight to a real fd (a terminal, or
        # here, a file).
        stderr_path = profile_dir / "soffice-stderr.log"
        with open(stderr_path, "wb") as stderr_file:
            proc = subprocess.Popen(
                [
                    soffice_bin,
                    "--headless",
                    "--invisible",
                    "--norestore",
                    f"-env:UserInstallation=file://{profile_dir}",
                    str(docx_path),
                    "macro:///Standard.Module1.UpdateAndSave",
                ],
                stdout=subprocess.DEVNULL,
                stderr=stderr_file,
                start_new_session=True,  # own process group; see _kill_process_tree
            )
            try:
                returncode = proc.wait(timeout=timeout_seconds)
            except subprocess.TimeoutExpired:
                _kill_process_tree(proc)
                raise FieldRecalculationError(
                    f"LibreOffice did not finish within {timeout_seconds}s recalculating {docx_path} "
                    "and was force-killed. This has been observed to hang intermittently on macOS "
                    "(reproduced both in a sandboxed environment and a plain native terminal) -- see "
                    "this module's docstring and the repo-root README.md's 'Status and known limitations' recalculation' section."
                ) from None

        if returncode != 0:
            stderr_text = stderr_path.read_text(errors="replace") if stderr_path.exists() else ""
            raise FieldRecalculationError(
                f"LibreOffice field recalculation failed (exit {returncode}):\n{stderr_text}"
            )

    # A clean exit code alone isn't trustworthy here: reproduced a run that
    # exited 0 within seconds without the macro actually having run (the
    # file was untouched, ToC field still showing the un-recalculated
    # placeholder). Verify the actual expected side effect happened rather
    # than just trusting the process exit status.
    if _still_has_unrecalculated_toc_placeholder(docx_path):
        raise FieldRecalculationError(
            f"LibreOffice exited successfully but {docx_path} still shows the "
            "un-recalculated ToC placeholder ('Right-click to update field') -- the macro "
            "did not actually run, or errored internally without a nonzero exit code."
        )

    return docx_path


def _still_has_unrecalculated_toc_placeholder(docx_path: Path) -> bool:
    import docx as docx_lib  # local import: only needed for this check

    document = docx_lib.Document(str(docx_path))
    for paragraph in document.paragraphs:
        if "Right-click to update field" in paragraph.text:
            return True
    return False
