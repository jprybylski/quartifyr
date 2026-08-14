import re

import pytest

from quartifyr_styling.abbreviations import (
    AbbreviationsError,
    build_abbreviations_tex,
    load_abbreviations,
    render_abbreviations_tex,
)

# Mirrors the regex quarto-plus's terms_and_abbreviations.lua uses to parse
# abbreviations.tex, so we can prove our output round-trips through it.
_NEWACRONYM_RE = re.compile(r"\\newacronym\{([^}]+)\}\{([^}]+)\}\{([^}]+)\}")


def _write_footnotes_yaml(tmp_path, abbreviations: dict[str, str]):
    import yaml

    path = tmp_path / "standard_footnotes.yaml"
    path.write_text(yaml.safe_dump({"abbreviations": abbreviations, "figure_footnotes": {}}))
    return path


def test_load_abbreviations_reads_block(tmp_path):
    path = _write_footnotes_yaml(tmp_path, {"PK": "pharmacokinetic", "AE": "adverse event"})
    result = load_abbreviations(path)
    assert result == {"PK": "pharmacokinetic", "AE": "adverse event"}


def test_missing_abbreviations_block_raises(tmp_path):
    path = tmp_path / "empty.yaml"
    path.write_text("figure_footnotes: {}\n")
    with pytest.raises(AbbreviationsError):
        load_abbreviations(path)


def test_simple_key_passes_through_unchanged():
    tex = render_abbreviations_tex({"PK": "pharmacokinetic"})
    assert tex == "\\newacronym{PK}{PK}{pharmacokinetic}\n"


def test_subscript_key_converts_for_sorting_and_markdown():
    tex = render_abbreviations_tex({"AUC_{0-24}": "area under the curve from 0 to 24 hours"})
    match = _NEWACRONYM_RE.match(tex.strip())
    assert match is not None
    sorting_key, markdown_form, definition = match.groups()
    assert sorting_key == "AUC0-24"
    assert markdown_form == "AUC~0-24~"
    assert definition == "area under the curve from 0 to 24 hours"


def test_multiple_entries_each_produce_a_parseable_line():
    abbrevs = {
        "PK": "pharmacokinetic",
        "C_{max}": "peak (maximum) concentration",
        "t_{1/2}": "elimination half-life",
    }
    tex = render_abbreviations_tex(abbrevs)
    lines = [line for line in tex.splitlines() if line.strip()]
    assert len(lines) == len(abbrevs)
    for line in lines:
        assert _NEWACRONYM_RE.match(line) is not None


def test_brace_in_definition_raises_clear_error():
    with pytest.raises(AbbreviationsError, match="literal"):
        render_abbreviations_tex({"PK": "pharmaco{kinetic}"})


def test_build_abbreviations_tex_writes_file(tmp_path):
    footnotes = _write_footnotes_yaml(tmp_path, {"PK": "pharmacokinetic"})
    out = build_abbreviations_tex(footnotes, tmp_path / "out" / "abbreviations.tex")
    assert out.exists()
    assert "\\newacronym{PK}{PK}{pharmacokinetic}" in out.read_text()


def test_realistic_reportifyr_subset_round_trips(tmp_path):
    # A representative slice of reportifyr's actual bundled
    # standard_footnotes.yaml abbreviations: block (plain keys, Greek
    # letters, and LaTeX-subscript keys all appear in the real file).
    abbrevs = {
        "AUC": "area under the curve",
        "ΔOFV": "change in objective function value",
        "AUC_{0-24}": "area under the concentration-time curve from time 0 to 24 hours",
        "CL/F": "apparent clearance",
        "C_{max,ss}": "peak (maximum) concentration at steady state",
    }
    footnotes = _write_footnotes_yaml(tmp_path, abbrevs)
    out = build_abbreviations_tex(footnotes, tmp_path / "abbreviations.tex")
    text = out.read_text()
    lines = [line for line in text.splitlines() if line.strip()]
    assert len(lines) == len(abbrevs)
    for line in lines:
        match = _NEWACRONYM_RE.match(line)
        assert match is not None, line
        sorting_key, markdown_form, _definition = match.groups()
        # sorting key must never retain the '_{...}' LaTeX notation
        assert "_{" not in sorting_key
        assert "}" not in sorting_key
