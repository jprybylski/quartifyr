from pathlib import Path

import pytest
import yaml

from quartifyr_styling.schema import StyleConfig
from quartifyr_styling.style_editing import StyleEditingError, copy_example_style, save_overrides, update_style

DEFAULT_YAML = Path(__file__).parent.parent.parent / "inst" / "python" / "styles" / "default.yaml"


def test_copy_example_style_writes_file_and_returns_parsed_content(tmp_path):
    dest = tmp_path / "style.yaml"
    parsed = copy_example_style(DEFAULT_YAML, dest)
    assert dest.exists()
    assert dest.read_text(encoding="utf-8") == DEFAULT_YAML.read_text(encoding="utf-8")
    assert parsed == yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))


def test_copy_example_style_refuses_to_overwrite_by_default(tmp_path):
    dest = tmp_path / "style.yaml"
    dest.write_text("existing: true\n")
    with pytest.raises(StyleEditingError):
        copy_example_style(DEFAULT_YAML, dest)
    assert dest.read_text() == "existing: true\n"


def test_copy_example_style_overwrite_true_replaces(tmp_path):
    dest = tmp_path / "style.yaml"
    dest.write_text("existing: true\n")
    copy_example_style(DEFAULT_YAML, dest, overwrite=True)
    assert "existing: true" not in dest.read_text()


def test_copy_example_style_missing_base_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        copy_example_style(tmp_path / "missing.yaml", tmp_path / "out.yaml")


def test_save_overrides_deconvolute_writes_only_the_diff(tmp_path):
    base = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    style = dict(base)
    style["heading"] = {**base["heading"], "all_caps": True}
    dest = tmp_path / "overrides.yaml"

    output = save_overrides(DEFAULT_YAML, style, dest, deconvolute=True)

    assert output == {"heading": {"all_caps": True}}
    assert yaml.safe_load(dest.read_text(encoding="utf-8")) == output


def test_save_overrides_no_deconvolute_writes_style_as_is(tmp_path):
    import json

    base = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    style = dict(base)
    style["heading"] = {**base["heading"], "all_caps": True}
    dest = tmp_path / "full.yaml"

    output = save_overrides(DEFAULT_YAML, style, dest, deconvolute=False)

    # JSON-normalized (string dict keys), not necessarily identical() to
    # the original -- see _json_normalize()'s own docstring. Re-parsing
    # through StyleConfig (which explicitly int()s heading-size keys) is
    # what actually matters, not key type equality here.
    normalized_style = json.loads(json.dumps(style))
    assert output == normalized_style
    assert yaml.safe_load(dest.read_text(encoding="utf-8")) == normalized_style


def test_save_overrides_output_still_loads_via_styleconfig(tmp_path):
    # The JSON-normalized (string-keyed) heading sizes written out by
    # save_overrides() (deconvolute=False, so the whole fonts.sizes.heading
    # subtree is present) must still parse back through StyleConfig, which
    # explicitly int()s each key -- confirms the quoted '1': 16 style keys
    # _json_normalize() produces are a cosmetic difference, not a real one.
    base = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    dest = tmp_path / "full.yaml"
    save_overrides(DEFAULT_YAML, base, dest, deconvolute=False)

    config = StyleConfig.load(dest)
    assert config.fonts.sizes.heading.get(1) == base["fonts"]["sizes"]["heading"][1]


def test_save_overrides_json_sourced_style_does_not_pull_in_int_keyed_subtrees(tmp_path):
    # Regression: yaml.safe_load parses fonts.sizes.heading's 1:/2:/...
    # keys as ints, but a `style` arriving via JSON (the real R/CLI path,
    # simulated here with a json round-trip) always has string keys --
    # diffing against a directly-yaml.safe_load()ed base used to see the
    # whole subtree as changed just from the key-type mismatch.
    import json

    base = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    style = json.loads(json.dumps(base))  # simulate the R/CLI JSON round-trip
    style["heading"]["all_caps"] = True
    dest = tmp_path / "overrides.yaml"

    output = save_overrides(DEFAULT_YAML, style, dest, deconvolute=True)

    assert output == {"heading": {"all_caps": True}}


def test_save_overrides_refuses_to_overwrite_by_default(tmp_path):
    dest = tmp_path / "overrides.yaml"
    dest.write_text("existing: true\n")
    with pytest.raises(StyleEditingError):
        save_overrides(DEFAULT_YAML, {"a": 1}, dest)


def test_update_style_merges_and_writes_when_confirmed(tmp_path):
    target = tmp_path / "style.yaml"
    target.write_text(yaml.safe_dump({"heading": {"bold": True, "all_caps": False}, "other": 1}))

    merged = update_style(target, {"heading": {"all_caps": True}}, prompt=lambda _msg: "y")

    assert merged == {"heading": {"bold": True, "all_caps": True}, "other": 1}
    assert yaml.safe_load(target.read_text(encoding="utf-8")) == merged


def test_update_style_assume_yes_skips_prompt(tmp_path):
    target = tmp_path / "style.yaml"
    target.write_text(yaml.safe_dump({"a": 1}))

    def _boom(_msg):
        raise AssertionError("prompt should not be called when assume_yes=True")

    merged = update_style(target, {"a": 2}, assume_yes=True, prompt=_boom)
    assert merged == {"a": 2}


def test_update_style_declining_raises_and_does_not_write(tmp_path):
    target = tmp_path / "style.yaml"
    original = yaml.safe_dump({"a": 1})
    target.write_text(original)

    with pytest.raises(StyleEditingError):
        update_style(target, {"a": 2}, prompt=lambda _msg: "n")
    assert target.read_text() == original


def test_update_style_json_sourced_update_does_not_duplicate_int_keys(tmp_path):
    # Same regression as save_overrides' -- updates arriving via JSON
    # (--updates-json/jsonlite::toJSON) always have string keys; merging
    # that onto a directly-yaml.safe_load()ed file used to leave both a
    # "1" and a 1 key in fonts.sizes.heading.
    import json

    target = tmp_path / "style.yaml"
    target.write_text(DEFAULT_YAML.read_text(encoding="utf-8"), encoding="utf-8")
    updates = json.loads(json.dumps({"fonts": {"sizes": {"heading": {"1": 99}}}}))

    merged = update_style(target, updates, assume_yes=True)

    assert merged["fonts"]["sizes"]["heading"] == {"1": 99, "2": 14, "3": 12, "4": 11, "5": 11, "6": 11}


def test_update_style_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        update_style(tmp_path / "missing.yaml", {"a": 1}, assume_yes=True)
