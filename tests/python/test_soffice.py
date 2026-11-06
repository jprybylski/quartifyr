"""Tests for the shared headless-LibreOffice plumbing, using fake ``soffice``
scripts so no real LibreOffice is needed."""

from __future__ import annotations

import os
import stat
import sys
import time
from pathlib import Path, PureWindowsPath

import pytest

from quartifyr_styling import _soffice
from quartifyr_styling._soffice import (
    SofficeNotFoundError,
    SofficeTimeoutError,
    profile_url,
    resolve_soffice,
    run_macro,
)
from quartifyr_styling.recalculate_fields import FieldRecalculationError, recalculate_fields

posix_only = pytest.mark.skipif(sys.platform == "win32", reason="fake soffice is a POSIX shell script")


def _fake_soffice(path: Path, body: str) -> Path:
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def test_profile_url_is_a_file_url_with_encoded_spaces(tmp_path):
    profile = tmp_path / "a profile dir"
    profile.mkdir()
    url = profile_url(profile)
    assert url.startswith("file:///")
    assert "%20" in url and " " not in url


def test_windows_paths_become_three_slash_urls():
    # What profile_url() relies on for Windows: Path.as_uri() on a Windows
    # path, not the naive "file://" + str(path) that gave file://C:\Users\...
    assert PureWindowsPath(r"C:\Users\me\AppData\Local\Temp\quartifyr-lo-profile-x").as_uri() == (
        "file:///C:/Users/me/AppData/Local/Temp/quartifyr-lo-profile-x"
    )


def test_resolve_soffice_missing_path_and_command(tmp_path):
    with pytest.raises(SofficeNotFoundError, match="does not exist or is not executable"):
        resolve_soffice(tmp_path / "nope" / "soffice")
    with pytest.raises(SofficeNotFoundError, match="not found on PATH"):
        resolve_soffice("definitely-not-a-real-binary")


@posix_only
def test_resolve_soffice_rejects_non_executable_file(tmp_path):
    plain = tmp_path / "soffice"
    plain.write_text("#!/bin/sh\n")
    with pytest.raises(SofficeNotFoundError, match="not executable"):
        resolve_soffice(plain)


@posix_only
def test_resolve_soffice_accepts_explicit_path(tmp_path):
    fake = _fake_soffice(tmp_path / "soffice", "exit 0\n")
    assert Path(resolve_soffice(fake)) == fake


@posix_only
def test_run_macro_passes_a_valid_profile_url_for_a_path_with_a_space(tmp_path):
    args_file = tmp_path / "args.txt"
    fake = _fake_soffice(tmp_path / "soffice", f'printf "%s\\n" "$@" > "{args_file}"\n')
    profile = tmp_path / "profile with space"
    profile.mkdir()
    returncode, _stderr = run_macro(
        str(fake),
        tmp_path / "x.docx",
        "macro:///Standard.Module1.Go",
        profile_dir=profile,
        stderr_path=tmp_path / "err.log",
        timeout_seconds=30,
    )
    assert returncode == 0
    args = args_file.read_text().splitlines()
    assert f"-env:UserInstallation={profile_url(profile)}" in args
    assert args[-1] == "macro:///Standard.Module1.Go"


@posix_only
def test_timeout_kills_the_detached_worker_and_reports_a_timeout(tmp_path):
    pid_file = tmp_path / "worker.pid"
    # The "launcher" starts a detached-looking worker and then waits, like
    # soffice -> soffice.bin.
    fake = _fake_soffice(tmp_path / "soffice", f'sleep 300 &\necho $! > "{pid_file}"\nwait\n')
    profile = tmp_path / "profile"
    profile.mkdir()
    with pytest.raises(SofficeTimeoutError):
        run_macro(
            str(fake),
            tmp_path / "x.docx",
            "macro:///Standard.Module1.Go",
            profile_dir=profile,
            stderr_path=tmp_path / "err.log",
            timeout_seconds=1,
        )
    worker = int(pid_file.read_text())
    for _ in range(50):
        if not _alive(worker):
            break
        time.sleep(0.1)
    assert not _alive(worker), "the soffice worker survived the timeout"


@posix_only
def test_recalculate_fields_timeout_is_a_timeout_and_cleans_up(tmp_path, monkeypatch):
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    monkeypatch.setattr("tempfile.tempdir", str(scratch))
    docx_path = tmp_path / "doc.docx"
    docx_path.write_bytes(b"not a real docx, just needs to exist")
    fake = _fake_soffice(tmp_path / "soffice", "sleep 300\n")
    with pytest.raises(FieldRecalculationError, match="did not finish within 1s"):
        recalculate_fields(docx_path, soffice_bin=str(fake), timeout_seconds=1)
    assert list(scratch.iterdir()) == []


def test_kill_process_tree_on_windows_uses_taskkill_and_a_command_line_sweep(monkeypatch):
    calls: list[list[str]] = []

    class _Proc:
        pid = 4242

        def wait(self, timeout=None):
            return 0

    def fake_run(cmd, **_kwargs):
        calls.append(list(cmd))

    monkeypatch.setattr(_soffice, "IS_WINDOWS", True)
    monkeypatch.setattr(_soffice.subprocess, "run", fake_run)
    _soffice.kill_process_tree(_Proc(), marker=r"C:\Temp\quartifyr-lo-profile-x")
    assert calls[0] == ["taskkill", "/T", "/F", "/PID", "4242"]
    assert calls[1][0] == "powershell"
    assert r"C:\Temp\quartifyr-lo-profile-x" in calls[1][-1]


def test_rmtree_retrying_gives_up_quietly(tmp_path, monkeypatch):
    target = tmp_path / "held"
    target.mkdir()

    def always_fail(_path):
        raise PermissionError("[WinError 32] in use")

    monkeypatch.setattr(_soffice.shutil, "rmtree", lambda path, ignore_errors=False: (
        None if ignore_errors else always_fail(path)
    ))
    # Must not raise even though every removal attempt fails.
    _soffice.rmtree_retrying(target, attempts=2, delay=0)
