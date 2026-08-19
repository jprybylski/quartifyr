"""Guards schema.json against drifting from schema.py -- the runtime
validator most style YAML consumers never see directly. A field added to
one but not the other is exactly the kind of thing this test exists to
catch (see issue #28: the JSON schema is meant to be evergreen, not a
one-time snapshot).
"""

import dataclasses
import json
from pathlib import Path

import yaml

from quartifyr_styling.schema import CodeStyle, EquationStyle, StyleConfig

SCHEMA_JSON = Path(__file__).parent.parent.parent / "inst" / "python" / "styles" / "schema.json"
DEFAULT_YAML = Path(__file__).parent.parent.parent / "inst" / "python" / "styles" / "default.yaml"


def _load_schema() -> dict:
    return json.loads(SCHEMA_JSON.read_text(encoding="utf-8"))


def test_schema_json_is_valid_json():
    _load_schema()


def test_schema_top_level_keys_match_style_config_fields():
    schema = _load_schema()
    dataclass_fields = {f.name for f in dataclasses.fields(StyleConfig)}
    assert set(schema["properties"].keys()) == dataclass_fields
    assert set(schema["required"]) == dataclass_fields


def test_schema_rejects_unknown_top_level_key():
    schema = _load_schema()
    assert schema.get("additionalProperties") is False


def test_identity_is_not_in_schema_or_default_yaml():
    # Regression: identity.org_name/logo_path were dead config (nothing
    # read them -- the real logo comes from the .qmd's `logo:`
    # frontmatter) and were removed as part of #28.
    schema = _load_schema()
    assert "identity" not in schema["properties"]
    default_dict = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    assert "identity" not in default_dict


def test_schema_heading_all_caps_present_and_optional():
    schema = _load_schema()
    heading_props = schema["properties"]["heading"]["properties"]
    assert "all_caps" in heading_props
    assert "all_caps" not in schema["properties"]["heading"]["required"]


def test_schema_code_and_equation_sections_match_dataclasses():
    schema = _load_schema()
    code_fields = {f.name for f in dataclasses.fields(CodeStyle)}
    assert set(schema["properties"]["code"]["properties"].keys()) == code_fields
    equation_fields = {f.name for f in dataclasses.fields(EquationStyle)}
    assert set(schema["properties"]["equation"]["properties"].keys()) == equation_fields


def test_default_yaml_top_level_keys_covered_by_schema():
    schema = _load_schema()
    default_dict = yaml.safe_load(DEFAULT_YAML.read_text(encoding="utf-8"))
    assert set(default_dict.keys()) <= set(schema["properties"].keys())
