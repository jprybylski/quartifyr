"""Sync the style-coupled keys in reportifyr's own ``report/config.yaml``
to a quartifyr style YAML.

reportifyr doesn't read quartifyr's style YAML at all -- its
``footnotes_font``/``footnotes_font_size`` keys (used to style the
Source/Notes/Abbreviations footnotes ``reportifyr::add_tables()``/
``add_figures()`` generate, see ``reportipyr/footnotes.py``) are scaffolded
independently and, left untouched, default to "Arial Narrow"/10 --
visually clashing with whatever a project's own style YAML sets for
``fonts.body``/``fonts.sizes.footnote``. Both bundled examples'
``report/config.yaml`` already carry a hand-written comment noting this
has to be kept in sync by hand; this module is that sync, done for you.

Deliberately narrow: these are the *only* two ``config.yaml`` keys any
part of a style YAML actually maps onto today (confirmed against
reportifyr's own Python engine, ``reportipyr/footnotes.py``) -- not a
general-purpose config.yaml editor.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml

from .schema import StyleConfig


class ReportifyrSyncError(ValueError):
    """Raised when ``report/config.yaml`` can't be read/updated."""


def _as_yaml_number(value: float) -> float | int:
    # yaml.safe_dump(9.0) writes "9.0", turning a diff-free no-op sync
    # into a needless float-vs-int churn against a config.yaml that (like
    # both bundled examples') was hand-authored with a plain integer.
    return int(value) if value == int(value) else value


def compute_synced_values(config: StyleConfig) -> dict[str, Any]:
    """The `report/config.yaml` keys/values a given style config maps onto."""
    return {
        "footnotes_font": config.fonts.body,
        "footnotes_font_size": _as_yaml_number(config.fonts.sizes.footnote),
    }


def sync_reportifyr_config(
    config: StyleConfig,
    config_yaml_path: str | Path,
    *,
    assume_yes: bool = False,
    prompt=input,
    out=sys.stdout,
) -> bool:
    """Updates ``footnotes_font``/``footnotes_font_size`` in
    ``config_yaml_path`` to match ``config``, in place.

    No-ops (returns ``False``, writes nothing) if both keys already match.
    Otherwise prints the change and, unless ``assume_yes``, requires an
    interactive ``y``/``yes`` confirmation (read via ``prompt``, `input()`
    by default -- swappable for tests) before writing; declining raises
    `ReportifyrSyncError` rather than silently skipping, so a non-interactive
    caller can't mistake "declined" for "already in sync". Returns ``True``
    once written.

    Rewrites the whole file via `yaml.safe_dump` -- like any full-file YAML
    rewrite, this drops comments and any formatting `config_yaml_path` had
    (including the very "keep this in sync by hand" comment this function
    makes obsolete).
    """
    config_yaml_path = Path(config_yaml_path)
    if not config_yaml_path.exists():
        raise FileNotFoundError(f"reportifyr config.yaml not found: {config_yaml_path}")

    existing = yaml.safe_load(config_yaml_path.read_text(encoding="utf-8")) or {}
    if not isinstance(existing, dict):
        raise ReportifyrSyncError(f"{config_yaml_path} did not parse as a YAML mapping")

    target = compute_synced_values(config)
    changes = {k: v for k, v in target.items() if existing.get(k) != v}
    if not changes:
        return False

    print(f"The following keys in {config_yaml_path} are out of sync with the style YAML:", file=out)
    for key, new_value in changes.items():
        print(f"  {key}: {existing.get(key)!r} -> {new_value!r}", file=out)

    if not assume_yes:
        answer = prompt("Update report/config.yaml to match? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            raise ReportifyrSyncError("sync declined -- report/config.yaml was not changed")

    updated = dict(existing)
    updated.update(changes)
    config_yaml_path.write_text(yaml.safe_dump(updated, sort_keys=False), encoding="utf-8")
    return True
