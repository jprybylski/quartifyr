"""Windows-only behaviour of the shared LibreOffice launcher, against real processes.

The POSIX tests in test_soffice.py use shell-script fakes; these use a ``.bat``
launcher and a Python "worker" standing in for ``soffice.bin``. They check what
#86 is about and nothing else can: that a timeout leaves no process behind,
that the command-line sweep finds a worker whose launcher is already gone
(the case ``taskkill /T`` cannot reach) without killing itself or bystanders,
and that a profile path with a space reaches LibreOffice as a valid URL.
"""

from __future__ import annotations

import subprocess
import sys
import textwrap
import time
from pathlib import Path

import pytest

from quartifyr_styling import _soffice
from quartifyr_styling._soffice import (
    SofficeTimeoutError,
    _sweep_script,
    kill_process_tree,
    profile_url,
    rmtree_retrying,
    run_macro,
)
from quartifyr_styling.recalculate_fields import FieldRecalculationError, recalculate_fields

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="Windows process handling")

WORKER = textwrap.dedent(
    """
    import sys, time, pathlib
    pathlib.Path(sys.argv[1]).write_text(str(__import__("os").getpid()))
    time.sleep(300)
    """
)


def _alive(pid: int) -> bool:
    out = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True, check=False
    ).stdout
    return f" {pid} " in out or out.split()[1:2] == [str(pid)]


def _wait_for(path: Path, seconds: float = 20) -> int:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.exists() and path.read_text().strip():
            return int(path.read_text())
        time.sleep(0.1)
    raise AssertionError(f"{path} was never written")


def _wait_dead(pid: int, seconds: float = 15) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if not _alive(pid):
            return True
        time.sleep(0.2)
    return not _alive(pid)


@pytest.fixture
def worker(tmp_path):
    path = tmp_path / "worker.py"
    path.write_text(WORKER)
    return path


@pytest.fixture
def cleanup():
    pids: list[int] = []
    yield pids
    for pid in pids:
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True, check=False)


def _blocking_launcher(tmp_path: Path, worker: Path, pid_file: Path) -> Path:
    """A soffice.exe stand-in that stays alive while its worker runs (cmd.exe -> python)."""
    launcher = tmp_path / "soffice.bat"
    launcher.write_text(f'@echo off\r\n"{sys.executable}" "{worker}" "{pid_file}" %*\r\n')
    return launcher


def test_a_timeout_leaves_no_worker_and_is_reported_as_a_timeout(tmp_path, worker):
    pid_file = tmp_path / "pid.txt"
    launcher = _blocking_launcher(tmp_path, worker, pid_file)
    profile = tmp_path / "profile with space"
    profile.mkdir()

    with pytest.raises(SofficeTimeoutError):
        run_macro(
            str(launcher), tmp_path / "x.docx", "macro:///Standard.Module1.Go",
            profile_dir=profile, stderr_path=tmp_path / "err.log", timeout_seconds=4,
        )

    assert _wait_dead(_wait_for(pid_file)), "the worker survived the timeout"


def test_the_sweep_finds_a_worker_whose_launcher_is_already_gone(tmp_path, worker, cleanup):
    profile = tmp_path / "profile with space"
    profile.mkdir()
    url = profile_url(profile)
    pid_file = tmp_path / "pid.txt"
    # A launcher that starts the worker detached and exits at once, like soffice.exe -> soffice.bin.
    launcher = tmp_path / "detach.bat"
    # (In a batch file a literal % must be written %%: %20 would be argument 2 plus "0".)
    batch_url = url.replace("%", "%%")
    launcher.write_text(
        f'@echo off\r\nstart "" /b "{sys.executable}" "{worker}" "{pid_file}" "-env:UserInstallation={batch_url}"\r\n'
    )
    proc = subprocess.Popen([str(launcher)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    worker_pid = _wait_for(pid_file)
    cleanup.append(worker_pid)
    commandline = subprocess.run(
        ["powershell", "-NoProfile", "-Command", f"(Get-CimInstance Win32_Process -Filter 'ProcessId={worker_pid}').CommandLine"],
        capture_output=True, text=True, check=False,
    ).stdout
    assert url in commandline, f"test setup: the worker's command line is {commandline!r}"
    proc.wait(timeout=20)
    assert _alive(worker_pid), "test setup: the worker should outlive its launcher"

    kill_process_tree(proc, marker=url)

    assert _wait_dead(worker_pid), "the sweep did not find the worker by the profile URL on its command line"


def test_the_sweep_spares_other_processes_and_itself(tmp_path, worker, cleanup):
    profile = tmp_path / "profile"
    profile.mkdir()
    url = profile_url(profile)
    pid_target, pid_control = tmp_path / "target.pid", tmp_path / "control.pid"
    target = subprocess.Popen([sys.executable, str(worker), str(pid_target), f"-env:UserInstallation={url}"])
    control = subprocess.Popen([sys.executable, str(worker), str(pid_control), "-env:UserInstallation=file:///C:/other"])
    cleanup.extend([target.pid, control.pid])
    _wait_for(pid_target)
    _wait_for(pid_control)

    result = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", _sweep_script(url)],
        capture_output=True, text=True, timeout=60, check=False,
    )

    # It finished normally (it would not have, had it killed its own process) ...
    assert result.returncode == 0, result.stderr
    # ... took the matching worker ...
    assert _wait_dead(target.pid)
    # ... and left an unrelated one alone.
    assert _alive(control.pid)


def test_the_sweep_matches_case_insensitively(tmp_path, worker, cleanup):
    profile = tmp_path / "Profile"
    profile.mkdir()
    url = profile_url(profile)
    pid_file = tmp_path / "pid.txt"
    proc = subprocess.Popen([sys.executable, str(worker), str(pid_file), f"-env:UserInstallation={url.upper().replace('FILE', 'file')}"])
    cleanup.append(proc.pid)
    _wait_for(pid_file)

    subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", _sweep_script(url)],
        capture_output=True, timeout=60, check=False,
    )

    assert _wait_dead(proc.pid)


def test_a_profile_path_with_a_space_reaches_the_launcher_as_a_file_url(tmp_path):
    args_file = tmp_path / "args.txt"
    launcher = tmp_path / "soffice.bat"
    launcher.write_text(f'@echo off\r\necho %* > "{args_file}"\r\n')
    profile = tmp_path / "My Profile"
    profile.mkdir()

    returncode, _stderr = run_macro(
        str(launcher), tmp_path / "x.docx", "macro:///Standard.Module1.Go",
        profile_dir=profile, stderr_path=tmp_path / "err.log", timeout_seconds=30,
    )

    assert returncode == 0
    recorded = args_file.read_text()
    assert f"-env:UserInstallation={profile_url(profile)}" in recorded
    assert "file:///" in recorded and "%20" in recorded and "\\" not in recorded.split("UserInstallation=")[1].split()[0]


def test_cleanup_does_not_raise_while_a_file_is_still_open(tmp_path):
    held = tmp_path / "held"
    held.mkdir()
    handle = open(held / "soffice-stderr.log", "wb")  # what a dying LibreOffice still has open
    try:
        rmtree_retrying(held, attempts=2, delay=0.1)  # must not raise PermissionError
    finally:
        handle.close()
    rmtree_retrying(held, attempts=2, delay=0.1)
    assert not held.exists()


def test_recalculate_fields_timeout_on_windows_is_a_timeout_not_a_permission_error(tmp_path, worker):
    pid_file = tmp_path / "pid.txt"
    launcher = _blocking_launcher(tmp_path, worker, pid_file)
    docx_path = tmp_path / "doc.docx"
    docx_path.write_bytes(b"not a real docx, just needs to exist")

    with pytest.raises(FieldRecalculationError, match="did not finish|unavailable"):
        recalculate_fields(docx_path, soffice_bin=str(launcher), timeout_seconds=6)

    # (The fake's argument handling is irrelevant; what matters is that it
    # ended as the step's own error and not as a PermissionError, and that the
    # worker is gone.)
    if pid_file.exists() and pid_file.read_text().strip():
        assert _wait_dead(int(pid_file.read_text()))
