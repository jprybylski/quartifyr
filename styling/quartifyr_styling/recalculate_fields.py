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
"""

from __future__ import annotations

import shutil
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
    (standard_dir / "Module1.xba").write_text(_MACRO_XBA)
    (standard_dir / "script.xlb").write_text(_SCRIPT_XLB)
    (profile_dir / "user" / "basic" / "script.xlc").write_text(_SCRIPT_XLC)


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
        try:
            with open(stderr_path, "wb") as stderr_file:
                result = subprocess.run(
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
                    timeout=timeout_seconds,
                )
        except subprocess.TimeoutExpired as exc:
            raise FieldRecalculationError(
                f"LibreOffice did not finish within {timeout_seconds}s recalculating {docx_path}. "
                "This has been observed when a document's *non-index* text fields (not the main "
                "ToC) trigger a LibreOffice headless hang -- see this module's docstring."
            ) from exc

        if result.returncode != 0:
            stderr_text = stderr_path.read_text(errors="replace") if stderr_path.exists() else ""
            raise FieldRecalculationError(
                f"LibreOffice field recalculation failed (exit {result.returncode}):\n{stderr_text}"
            )

    return docx_path
