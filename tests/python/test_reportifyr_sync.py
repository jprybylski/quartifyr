from pathlib import Path

import pytest
import yaml

from quartifyr_styling.reportifyr_sync import ReportifyrSyncError, sync_reportifyr_config
from quartifyr_styling.schema import StyleConfig

DEFAULT_YAML = Path(__file__).parent.parent.parent / "inst" / "python" / "styles" / "default.yaml"


def _config():
    return StyleConfig.load(DEFAULT_YAML)


def _write_config_yaml(tmp_path, **fields):
    base = {
        "report_dir_name": "report",
        "footnotes_font": "Arial Narrow",
        "footnotes_font_size": 10,
    }
    base.update(fields)
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(base, sort_keys=False))
    return path


def test_noop_when_already_in_sync(tmp_path):
    config = _config()
    path = _write_config_yaml(tmp_path, footnotes_font=config.fonts.body, footnotes_font_size=int(config.fonts.sizes.footnote))
    changed = sync_reportifyr_config(config, path, assume_yes=True)
    assert changed is False


def test_writes_when_confirmed(tmp_path):
    config = _config()
    path = _write_config_yaml(tmp_path)
    changed = sync_reportifyr_config(config, path, assume_yes=True)
    assert changed is True
    updated = yaml.safe_load(path.read_text())
    assert updated["footnotes_font"] == config.fonts.body
    assert updated["footnotes_font_size"] == int(config.fonts.sizes.footnote)


def test_preserves_unrelated_keys(tmp_path):
    config = _config()
    path = _write_config_yaml(tmp_path, save_table_rtf=False, fig_alignment="center")
    sync_reportifyr_config(config, path, assume_yes=True)
    updated = yaml.safe_load(path.read_text())
    assert updated["save_table_rtf"] is False
    assert updated["fig_alignment"] == "center"


def test_declining_raises_and_does_not_write(tmp_path):
    config = _config()
    path = _write_config_yaml(tmp_path)
    original = path.read_text()
    with pytest.raises(ReportifyrSyncError):
        sync_reportifyr_config(config, path, assume_yes=False, prompt=lambda _msg: "n")
    assert path.read_text() == original


def test_confirming_via_prompt_writes(tmp_path):
    config = _config()
    path = _write_config_yaml(tmp_path)
    changed = sync_reportifyr_config(config, path, assume_yes=False, prompt=lambda _msg: "y")
    assert changed is True


def test_missing_config_yaml_raises(tmp_path):
    config = _config()
    with pytest.raises(FileNotFoundError):
        sync_reportifyr_config(config, tmp_path / "missing.yaml", assume_yes=True)
