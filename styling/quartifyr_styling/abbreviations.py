"""Bridge from reportifyr's ``standard_footnotes.yaml`` (``abbreviations:``
block) to the ``abbreviations.tex`` pseudo-LaTeX format that
``quarto-plus``'s ``terms_and_abbreviations.lua`` filter consumes.

One shared, org-wide YAML is the source of truth: ``reportifyr`` already
reads its ``abbreviations:`` block to resolve table/figure footnotes, so the
document's List of Abbreviations reuses the exact same file instead of a
second format to hand-maintain. Authors reference an abbreviation in the
``.qmd`` body with ``\\gls{}``/``\\Gls{}``/``\\glspl{}``/``\\Glspl{}`` (see
``quarto-plus``); only entries actually referenced end up in the rendered
list.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml

_SUBSCRIPT_RE = re.compile(r"_\{([^{}]*)\}")


class AbbreviationsError(ValueError):
    """Raised when the source YAML or a resulting entry can't be converted."""


def _to_markdown_form(key: str) -> str:
    """Convert LaTeX-style ``_{...}`` subscript notation to pandoc ``~...~``.

    E.g. ``AUC_{0-24}`` -> ``AUC~0-24~``, which pandoc renders as a real
    subscript in the rendered docx. Keys with no such notation pass through
    unchanged.
    """
    return _SUBSCRIPT_RE.sub(lambda m: f"~{m.group(1)}~", key)


def _to_sorting_key(key: str) -> str:
    """Strip ``_{...}`` down to bare adjacent text, for a stable plain-text sort."""
    return _SUBSCRIPT_RE.sub(lambda m: m.group(1), key)


def _require_no_braces(value: str, *, field: str, abbrev_key: str) -> str:
    if "{" in value or "}" in value:
        raise AbbreviationsError(
            f"abbreviation {abbrev_key!r}: {field} contains a literal '{{' or '}}', "
            "which the quarto-plus abbreviations.tex parser can't handle "
            "(only '_{...}' subscript notation in the *key* is supported)"
        )
    return value


def load_abbreviations(footnotes_yaml: str | Path) -> dict[str, str]:
    """Read the ``abbreviations:`` block out of a reportifyr-style footnotes YAML."""
    path = Path(footnotes_yaml)
    data = yaml.safe_load(path.read_text()) or {}
    abbreviations = data.get("abbreviations")
    if not abbreviations:
        raise AbbreviationsError(f"{path} has no top-level 'abbreviations:' block")
    return {str(k): str(v) for k, v in abbreviations.items()}


def render_abbreviations_tex(abbreviations: dict[str, str]) -> str:
    """Render ``{sorting_key: definition}`` pairs as ``\\newacronym{...}{...}{...}`` lines."""
    lines = []
    for key, definition in abbreviations.items():
        sorting_key = _require_no_braces(_to_sorting_key(key), field="sorting key", abbrev_key=key)
        markdown_form = _require_no_braces(_to_markdown_form(key), field="markdown form", abbrev_key=key)
        definition = _require_no_braces(definition, field="definition", abbrev_key=key)
        lines.append(f"\\newacronym{{{sorting_key}}}{{{markdown_form}}}{{{definition}}}")
    return "\n".join(lines) + "\n"


def build_abbreviations_tex(footnotes_yaml: str | Path, output_path: str | Path) -> Path:
    """Read ``footnotes_yaml`` and write the resulting ``abbreviations.tex`` to ``output_path``."""
    abbreviations = load_abbreviations(footnotes_yaml)
    text = render_abbreviations_tex(abbreviations)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text)
    return output_path
