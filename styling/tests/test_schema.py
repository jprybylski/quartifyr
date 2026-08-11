from pathlib import Path

import pytest

from quartifyr_styling.schema import StyleConfig, StyleConfigError, deep_merge

DEFAULT_YAML = Path(__file__).parent.parent / "styles" / "default.yaml"


def test_deep_merge_replaces_scalars_and_merges_dicts():
    base = {"a": 1, "b": {"c": 2, "d": 3}}
    override = {"b": {"c": 20}, "e": 5}
    merged = deep_merge(base, override)
    assert merged == {"a": 1, "b": {"c": 20, "d": 3}, "e": 5}
    # base is untouched
    assert base == {"a": 1, "b": {"c": 2, "d": 3}}


def test_default_yaml_loads_and_validates():
    config = StyleConfig.load(DEFAULT_YAML)
    assert config.fonts.body == "Times New Roman"
    assert config.fonts.heading == "Times New Roman"
    assert config.colors.text == "#000000"
    assert config.colors.heading == "#000000"
    assert config.page.size == "letter"
    assert config.fonts.sizes.heading.get(1) == 16
    assert config.fonts.sizes.heading.get(99) == config.fonts.sizes.heading.get(6)


def test_override_yaml_is_deep_merged(tmp_path):
    override_path = tmp_path / "org.yaml"
    override_path.write_text(
        "colors:\n"
        "  heading: '#123456'\n"
        "fonts:\n"
        "  body: 'Georgia'\n"
    )
    config = StyleConfig.load(DEFAULT_YAML, override_path)
    assert config.colors.heading == "#123456"
    assert config.fonts.body == "Georgia"
    # Untouched fields keep the base default.
    assert config.colors.text == "#000000"
    assert config.fonts.heading == "Times New Roman"


def test_invalid_hex_color_rejected(tmp_path):
    override_path = tmp_path / "bad.yaml"
    override_path.write_text("colors:\n  text: 'black'\n")
    with pytest.raises(StyleConfigError):
        StyleConfig.load(DEFAULT_YAML, override_path)


def test_non_positive_size_rejected(tmp_path):
    override_path = tmp_path / "bad.yaml"
    override_path.write_text("fonts:\n  sizes:\n    body: -1\n")
    with pytest.raises(StyleConfigError):
        StyleConfig.load(DEFAULT_YAML, override_path)


def test_invalid_page_size_rejected(tmp_path):
    override_path = tmp_path / "bad.yaml"
    override_path.write_text("page:\n  size: 'legal'\n")
    with pytest.raises(StyleConfigError):
        StyleConfig.load(DEFAULT_YAML, override_path)


def test_missing_required_key_reports_clear_error():
    with pytest.raises(StyleConfigError):
        StyleConfig.from_dict({"fonts": {}})
