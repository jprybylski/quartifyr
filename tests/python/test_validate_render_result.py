"""scripts/validate_render_result.py, which CI runs on real `render.R --json` output."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

pytest.importorskip("jsonschema")

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "validate_render_result.py"
spec = importlib.util.spec_from_file_location("validate_render_result", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FINISHED = {
    "schema_version": 1,
    "status": "ok",
    "errors": [],
    "artifacts": [],
    "inputs": [],
    "versions": {"quartifyr": "0.3.2", "libreoffice": None},
}


def _write(tmp_path, name, payload):
    path = tmp_path / name
    path.write_text(json.dumps(payload))
    return str(path)


def test_accepts_a_finished_render_and_an_early_error(tmp_path):
    ok = _write(tmp_path, "ok.json", FINISHED)
    failed = _write(tmp_path, "failed.json", {"schema_version": 1, "status": "error", "errors": ["boom"]})
    assert module.main([f"{ok}=ok", f"{failed}=error"]) == 0


def test_rejects_a_finished_render_without_provenance(tmp_path, capsys):
    payload = {k: v for k, v in FINISHED.items() if k != "inputs"}
    path = _write(tmp_path, "thin.json", payload)
    assert module.main([f"{path}=ok"]) == 1
    assert "inputs" in capsys.readouterr().err


def test_rejects_the_wrong_status_and_unreadable_files(tmp_path, capsys):
    ok = _write(tmp_path, "ok.json", FINISHED)
    assert module.main([f"{ok}=error"]) == 1
    assert "expected 'error'" in capsys.readouterr().err
    assert module.main([f"{tmp_path / 'missing.json'}=ok"]) == 1


def test_usage_errors(tmp_path):
    assert module.main([]) == 2
    assert module.main(["no-status-here"]) == 2
