"""Convenience helpers for pulling and editing a project's own copy of
quartifyr's default style YAML (issue #27).

A style YAML is otherwise something a user either hand-writes from
scratch against ``schema.json``/``schema.py``'s validation rules, or
copies out of an installed package's ``system.file(...)`` path by hand.
These three operations -- pull a working copy, save just the edits back
out as an override, or merge a change onto an existing file in place --
are common enough (see issue #27's own discussion) to be worth a real
function/CLI subcommand each rather than three slightly-different
``file.copy()``/YAML-editing incantations per project.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import yaml

from .schema import deep_merge, diff_from_base


class StyleEditingError(ValueError):
    """Raised when copying, saving, or updating a style YAML fails."""


def _json_normalize(data: Any) -> Any:
    """Round-trips ``data`` through JSON, so any non-string mapping key
    (YAML permits them -- ``fonts.sizes.heading``'s ``1:``/``2:``/...
    levels parse as Python ints via ``yaml.safe_load``) becomes a string
    the same way JSON's spec already forces one to be.

    Both sides of every comparison/merge in this module need to already
    be in this same canonical form, or a real key -- not a value --
    difference (`{1: 16}` vs `{"1": 16}`) reads as a value difference:
    confirmed the hard way, `diff_from_base` recursing into a mismatched
    subtree like that finds *every* entry "different" and pulls the
    whole subtree into the diff. Applied to *every* input here (a YAML
    file just loaded, or a caller-supplied dict, regardless of whether
    that dict already happened to come from JSON) rather than assuming
    which side needs it -- cheap, and correct either way.
    """
    return json.loads(json.dumps(data))


def _load_yaml_json_normalized(path: str | Path) -> dict[str, Any]:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    return _json_normalize(data)


def copy_example_style(base_path: str | Path, dest_path: str | Path, *, overwrite: bool = False) -> dict[str, Any]:
    """Copies ``base_path`` (typically ``styles/default.yaml``) to
    ``dest_path`` verbatim, and returns its parsed content -- a working
    copy a user can hand-edit directly, or edit as a returned R list and
    hand to ``save_overrides()`` below.
    """
    base_path = Path(base_path)
    dest_path = Path(dest_path)
    if not base_path.exists():
        raise FileNotFoundError(f"base style YAML not found: {base_path}")
    if dest_path.exists() and not overwrite:
        raise StyleEditingError(f"{dest_path} already exists -- pass overwrite=True/--overwrite to replace it")

    content = base_path.read_text(encoding="utf-8")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_text(content, encoding="utf-8")
    return yaml.safe_load(content)


def save_overrides(
    base_path: str | Path,
    style: dict[str, Any],
    dest_path: str | Path,
    *,
    overwrite: bool = False,
    deconvolute: bool = True,
) -> dict[str, Any]:
    """Saves ``style`` (typically a full style dict, edited from
    ``copy_example_style()``'s return value) to ``dest_path``.

    With ``deconvolute`` (the default), saves only the keys that differ
    from ``base_path``'s own content (``diff_from_base()``) -- an override
    YAML meant to be deep-merged back onto that same base at load time
    (``StyleConfig.load(base, override)``), not a second full style YAML
    to keep in sync by hand. ``deconvolute=False`` saves ``style`` as-is.
    """
    dest_path = Path(dest_path)
    if dest_path.exists() and not overwrite:
        raise StyleEditingError(f"{dest_path} already exists -- pass overwrite=True/--overwrite to replace it")

    style = _json_normalize(style)
    output = style
    if deconvolute:
        base = _load_yaml_json_normalized(base_path)
        output = diff_from_base(base, style)

    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_text(yaml.safe_dump(output, sort_keys=False), encoding="utf-8")
    return output


def update_style(
    file_path: str | Path,
    updates: dict[str, Any],
    *,
    assume_yes: bool = False,
    prompt=input,
    out=None,
) -> dict[str, Any]:
    """Deep-merges ``updates`` onto ``file_path``'s existing content, in
    place -- a ``modifyList()``-style edit of one section of a style YAML
    without hand-copying the rest of the file.

    Requires an interactive ``y``/``yes`` confirmation unless
    ``assume_yes``, since this rewrites the whole file via
    `yaml.safe_dump` and so drops any comments/formatting it had --
    raises `StyleEditingError` if declined, same as
    `reportifyr_sync.sync_reportifyr_config`'s identical tradeoff.
    """
    out = sys.stdout if out is None else out
    file_path = Path(file_path)
    if not file_path.exists():
        raise FileNotFoundError(f"style YAML not found: {file_path}")

    existing = _load_yaml_json_normalized(file_path)
    updates = _json_normalize(updates)
    merged = deep_merge(existing, updates)

    if not assume_yes:
        print(f"This will overwrite {file_path}, applying:", file=out)
        print(yaml.safe_dump(updates, sort_keys=False), file=out)
        print("Any existing comments/formatting in the file will be lost.", file=out)
        answer = prompt("Proceed? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            raise StyleEditingError("update declined -- the style YAML was not changed")

    file_path.write_text(yaml.safe_dump(merged, sort_keys=False), encoding="utf-8")
    return merged
