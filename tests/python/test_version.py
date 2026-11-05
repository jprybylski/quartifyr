"""The version recorded in render results must match the packaged one."""

import tomllib
from pathlib import Path

import quartifyr_styling


def test_version_matches_pyproject():
    pyproject = Path(__file__).resolve().parents[2] / "pyproject.toml"
    declared = tomllib.loads(pyproject.read_text())["project"]["version"]
    assert quartifyr_styling.__version__ == declared
