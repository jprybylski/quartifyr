"""Shared headless-LibreOffice plumbing for the two macro-driven steps
(``recalculate_fields.py`` and ``same_page_crossrefs.py``).

Both steps launch ``soffice --headless ... <docx> macro:///...`` with a
throwaway, pre-seeded profile and need exactly the same things around that
launch: find the executable, express the profile as a valid ``file:`` URL,
wait with a timeout, and make sure a timed-out run leaves no LibreOffice
processes behind. Keeping that here means a platform fix lands in both steps.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

IS_WINDOWS = sys.platform == "win32"


class SofficeError(RuntimeError):
    """Base class for failures launching or waiting on LibreOffice."""


class SofficeNotFoundError(SofficeError):
    """The requested LibreOffice executable does not exist or is not executable."""


class SofficeTimeoutError(SofficeError):
    """LibreOffice did not finish within the timeout and was force-killed."""


class SofficeUnavailableError(SofficeError):
    """LibreOffice never started the macro (a hung or unusable installation)."""


SOFFICE_BIN_ENV = "QUARTIFYR_SOFFICE_BIN"


def resolve_soffice(soffice_bin: str | os.PathLike[str] | None = None) -> str:
    """Return the full path of the LibreOffice executable to run.

    ``soffice_bin`` is either a bare command name looked up on ``PATH`` or a
    path to the executable; ``None`` means ``$QUARTIFYR_SOFFICE_BIN`` if set,
    else ``soffice`` on ``PATH`` (the same order the R side uses). Raises
    :class:`SofficeNotFoundError` with one clear message for a missing or
    non-executable target.
    """
    if soffice_bin is None:
        soffice_bin = os.environ.get(SOFFICE_BIN_ENV) or "soffice"
    requested = os.fspath(soffice_bin)
    found = shutil.which(requested)
    if found is None:
        if os.sep in requested or (os.altsep and os.altsep in requested) or Path(requested).is_absolute():
            raise SofficeNotFoundError(
                f"LibreOffice executable '{requested}' does not exist or is not executable"
            )
        raise SofficeNotFoundError(
            f"'{requested}' not found on PATH -- install LibreOffice "
            "(e.g. `brew install --cask libreoffice`) or pass its path explicitly "
            "(--soffice-bin / QUARTIFYR_SOFFICE_BIN)"
        )
    return found


def profile_url(profile_dir: str | os.PathLike[str]) -> str:
    """The ``file:///...`` URL LibreOffice's ``-env:UserInstallation`` expects.

    ``Path.as_uri()`` produces ``file:///C:/Users/...`` on Windows (a naive
    ``file://{path}`` gives ``file://C:\\Users\\...``, which LibreOffice
    doesn't treat as the seeded profile) and percent-encodes spaces on every
    platform.
    """
    return Path(profile_dir).resolve().as_uri()


def _powershell_kill_by_marker(marker: str) -> None:
    """Kill every process whose command line mentions ``marker``.

    ``soffice.exe`` can hand off to a ``soffice.bin`` and exit, after which
    ``taskkill /T`` (which follows parent->child links) can no longer reach
    it. Our throwaway profile directory is on the worker's command line, so it
    identifies exactly the processes this call started.
    """
    escaped = marker.replace("'", "''")
    script = (
        "Get-CimInstance Win32_Process | "
        f"Where-Object {{ $_.CommandLine -and $_.CommandLine.Contains('{escaped}') }} | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    )
    try:
        subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def kill_process_tree(proc: subprocess.Popen, *, marker: str | None = None) -> None:
    """Kill ``proc`` and everything it started.

    POSIX: ``proc`` was launched with ``start_new_session=True``, so killing
    its process group reaches the detached ``soffice.bin`` worker that a plain
    ``proc.kill()`` misses. Windows has no process groups in that sense:
    ``taskkill /T /F`` takes the launcher's tree, then (when ``marker`` is
    given, normally the profile directory) a sweep by command line catches a
    worker the launcher already detached.
    """
    if IS_WINDOWS:
        try:
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(proc.pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=30,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            pass
        if marker:
            _powershell_kill_by_marker(marker)
    else:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def rmtree_retrying(path: str | os.PathLike[str], *, attempts: int = 5, delay: float = 0.5) -> None:
    """Best-effort removal of a temp directory a dying LibreOffice may still hold open."""
    for attempt in range(attempts):
        try:
            shutil.rmtree(path)
            return
        except FileNotFoundError:
            return
        except OSError:
            if attempt == attempts - 1:
                shutil.rmtree(path, ignore_errors=True)
                return
            time.sleep(delay)


def started_marker_basic(path: str | os.PathLike[str] | None) -> str:
    """Basic statements (XML-escaped, for an ``.xba``) that write ``path`` as
    the macro's first action, so :func:`run_macro` can tell a macro that never
    started from one that is merely slow. Empty when ``path`` is None."""
    if path is None:
        return ""
    escaped = xml_escape(str(path), {'"': "&quot;"})
    return (
        "\n    Dim nStarted As Integer"
        "\n    nStarted = FreeFile"
        f"\n    Open &quot;{escaped}&quot; For Output As #nStarted"
        "\n    Print #nStarted, &quot;started&quot;"
        "\n    Close #nStarted\n"
    )


def _launch(soffice: str, args: list[str], stderr_file) -> subprocess.Popen:
    popen_extra: dict = {}
    if IS_WINDOWS:
        popen_extra["creationflags"] = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    else:
        popen_extra["start_new_session"] = True  # own process group; see kill_process_tree
    return subprocess.Popen(
        [soffice, "--headless", "--invisible", "--norestore", *args],
        stdout=subprocess.DEVNULL,
        stderr=stderr_file,
        **popen_extra,
    )


def _read_text(path: Path) -> str:
    try:
        return Path(path).read_text(errors="replace")
    except OSError:
        return ""


def warm_up_profile(
    soffice: str,
    profile_dir: Path,
    *,
    stderr_path: Path,
    timeout_seconds: float = 60,
) -> bool:
    """Let LibreOffice initialise ``profile_dir`` before the macro files go in.

    Why this exists (confirmed on macOS 26.6 / LibreOffice 26.2.5.2): a fresh
    profile that already contains a seeded ``user/basic`` library when
    LibreOffice starts for the first time never runs the macro; the process
    just sits there until the caller's timeout. Starting LibreOffice once on
    an empty profile (``--terminate_after_init``, about a second), and seeding
    the macro afterwards, makes the very same command run it in under two
    seconds. Returns False when the warm-up itself failed or timed out; that
    is not an error, the caller seeds anyway and the start check in
    :func:`run_macro` reports an unusable LibreOffice.
    """
    profile_dir = Path(profile_dir)
    profile_dir.mkdir(parents=True, exist_ok=True)
    with open(stderr_path, "wb") as stderr_file:
        proc = _launch(
            soffice,
            ["--terminate_after_init", f"-env:UserInstallation={profile_url(profile_dir)}"],
            stderr_file,
        )
        try:
            proc.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            kill_process_tree(proc, marker=str(profile_dir.resolve()))
            return False
    return proc.returncode == 0


def run_macro(
    soffice: str,
    docx_path: str | os.PathLike[str],
    macro: str,
    *,
    profile_dir: Path,
    stderr_path: Path,
    timeout_seconds: float,
    started_path: Path | None = None,
    start_timeout_seconds: float = 30,
) -> tuple[int, str]:
    """Run ``soffice`` headless on ``docx_path`` with ``macro`` and a seeded profile.

    Returns ``(returncode, stderr_text)``. On timeout the whole process tree
    is killed and :class:`SofficeTimeoutError` raised. ``stderr`` goes to a
    real file, not a pipe: ``soffice --headless`` forks a detached
    ``soffice.bin`` that inherits it, and ``communicate()`` on a pipe then
    blocks forever waiting for a write end that never closes. The file is
    closed (so Windows can delete it) before this returns.

    ``started_path``: a file the macro writes as its first action. If it has
    not appeared after ``start_timeout_seconds`` the macro is never going to
    run (a LibreOffice that cannot start it just waits), so the process is
    killed and :class:`SofficeUnavailableError` raised in seconds instead of
    after the full ``timeout_seconds``.
    """
    started_at = time.monotonic()
    with open(stderr_path, "wb") as stderr_file:
        proc = _launch(
            soffice,
            [f"-env:UserInstallation={profile_url(profile_dir)}", str(docx_path), macro],
            stderr_file,
        )
        marker = str(Path(profile_dir).resolve())
        try:
            while True:
                try:
                    returncode = proc.wait(timeout=0.25)
                    break
                except subprocess.TimeoutExpired:
                    pass
                elapsed = time.monotonic() - started_at
                if elapsed >= timeout_seconds:
                    raise SofficeTimeoutError(f"LibreOffice did not finish within {timeout_seconds}s")
                if (
                    started_path is not None
                    and elapsed >= start_timeout_seconds
                    and not Path(started_path).exists()
                ):
                    raise SofficeUnavailableError(
                        f"LibreOffice is unavailable: it had not started the macro after "
                        f"{start_timeout_seconds:g}s, so the step was abandoned instead of waiting "
                        f"{timeout_seconds:g}s"
                    )
        except SofficeError:
            kill_process_tree(proc, marker=marker)
            raise

    return returncode, _read_text(stderr_path)
