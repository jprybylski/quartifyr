"""Typed schema for quartifyr's docx style YAML.

A style spec is loaded from a base YAML (normally ``styles/default.yaml``)
and optionally deep-merged with a per-org/per-project override YAML, so a
new organization's look is a small diff rather than a from-scratch file.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

_HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
_PAGE_SIZES = {"letter", "a4"}
_ALIGNMENTS = {"left", "justify", "center", "right"}


class StyleConfigError(ValueError):
    """Raised when a style YAML is malformed or fails validation."""


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge ``override`` onto ``base``, returning a new dict.

    Scalars and lists in ``override`` replace the corresponding value in
    ``base`` outright; only dicts are merged key-by-key.
    """
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _require_hex(value: str, field_name: str) -> str:
    if not isinstance(value, str) or not _HEX_COLOR_RE.match(value):
        raise StyleConfigError(
            f"{field_name} must be a '#RRGGBB' hex color, got: {value!r}"
        )
    return value


def _require_positive(value: Any, field_name: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise StyleConfigError(f"{field_name} must be a number, got: {value!r}") from exc
    if number <= 0:
        raise StyleConfigError(f"{field_name} must be positive, got: {value!r}")
    return number


def _require_nonnegative(value: Any, field_name: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise StyleConfigError(f"{field_name} must be a number, got: {value!r}") from exc
    if number < 0:
        raise StyleConfigError(f"{field_name} must not be negative, got: {value!r}")
    return number


def _require_alignment(value: Any, field_name: str) -> str:
    if value not in _ALIGNMENTS:
        raise StyleConfigError(f"{field_name} must be one of {_ALIGNMENTS}, got: {value!r}")
    return value


@dataclass
class HeadingSizes:
    levels: dict[int, float]

    def get(self, level: int) -> float:
        if level in self.levels:
            return self.levels[level]
        # Fall back to the smallest defined level for anything deeper.
        return self.levels[max(self.levels)]


@dataclass
class FontSizes:
    body: float
    title: float
    subtitle: float
    heading: HeadingSizes
    caption: float
    footnote: float
    toc: float

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "FontSizes":
        heading_raw = d.get("heading", {})
        levels = {int(k): _require_positive(v, f"fonts.sizes.heading[{k}]") for k, v in heading_raw.items()}
        if not levels:
            raise StyleConfigError("fonts.sizes.heading must define at least one level")
        return cls(
            body=_require_positive(d["body"], "fonts.sizes.body"),
            title=_require_positive(d["title"], "fonts.sizes.title"),
            subtitle=_require_positive(d["subtitle"], "fonts.sizes.subtitle"),
            heading=HeadingSizes(levels),
            caption=_require_positive(d["caption"], "fonts.sizes.caption"),
            footnote=_require_positive(d["footnote"], "fonts.sizes.footnote"),
            toc=_require_positive(d["toc"], "fonts.sizes.toc"),
        )


@dataclass
class Fonts:
    body: str
    heading: str
    monospace: str
    sizes: FontSizes

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Fonts":
        return cls(
            body=d["body"],
            heading=d["heading"],
            monospace=d["monospace"],
            sizes=FontSizes.from_dict(d["sizes"]),
        )


@dataclass
class Colors:
    text: str
    heading: str
    title: str
    caption: str
    table_header_fill: str
    table_border: str
    rule: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Colors":
        kwargs = {k: _require_hex(v, f"colors.{k}") for k, v in d.items()}
        return cls(**kwargs)


@dataclass
class Margins:
    top: float
    bottom: float
    left: float
    right: float

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Margins":
        return cls(**{k: _require_positive(v, f"page.margins_in.{k}") for k, v in d.items()})


@dataclass
class Page:
    size: str
    margins_in: Margins

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Page":
        size = d["size"]
        if size not in _PAGE_SIZES:
            raise StyleConfigError(f"page.size must be one of {_PAGE_SIZES}, got: {size!r}")
        return cls(size=size, margins_in=Margins.from_dict(d["margins_in"]))


@dataclass
class ParagraphStyle:
    line_spacing: float
    space_after_pt: float
    alignment: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "ParagraphStyle":
        return cls(
            line_spacing=_require_positive(d["line_spacing"], "paragraph.line_spacing"),
            space_after_pt=_require_positive(d["space_after_pt"], "paragraph.space_after_pt"),
            alignment=_require_alignment(d["alignment"], "paragraph.alignment"),
        )


@dataclass
class HeadingStyle:
    bold: bool
    space_before_pt: float
    space_after_pt: float
    keep_with_next: bool
    all_caps: bool

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "HeadingStyle":
        return cls(
            bold=bool(d["bold"]),
            space_before_pt=_require_positive(d["space_before_pt"], "heading.space_before_pt"),
            space_after_pt=_require_positive(d["space_after_pt"], "heading.space_after_pt"),
            keep_with_next=bool(d["keep_with_next"]),
            # Visual transform only (OOXML w:caps) -- the underlying heading
            # text/string is untouched, so ToC entries/crossrefs still read
            # back the author's real casing. Default False preserves
            # existing rendered output for anyone not opting in.
            all_caps=bool(d.get("all_caps", False)),
        )


@dataclass
class TableStyle:
    style: str
    header_bold: bool
    banding: bool

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "TableStyle":
        return cls(style=d["style"], header_bold=bool(d["header_bold"]), banding=bool(d["banding"]))


@dataclass
class SynopsisStyle:
    """Governs the "Synopsis Label"/"Synopsis Value" paragraph styles that
    give the synopsis section a definition-list look (bold label line,
    indented value beneath it) without a real Word table -- see quartifyr
    issue #11 for why a table was rejected.
    """

    label_space_before_pt: float
    label_space_after_pt: float
    value_space_after_pt: float
    value_indent_in: float
    alignment: str | None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "SynopsisStyle":
        alignment = d.get("alignment")
        if alignment is not None:
            _require_alignment(alignment, "synopsis.alignment")
        return cls(
            label_space_before_pt=_require_positive(d["label_space_before_pt"], "synopsis.label_space_before_pt"),
            label_space_after_pt=_require_positive(d["label_space_after_pt"], "synopsis.label_space_after_pt"),
            value_space_after_pt=_require_positive(d["value_space_after_pt"], "synopsis.value_space_after_pt"),
            value_indent_in=_require_nonnegative(d["value_indent_in"], "synopsis.value_indent_in"),
            alignment=alignment,
        )


@dataclass
class TitlePageStyle:
    show_rule_under_title: bool
    fields: list[str]

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "TitlePageStyle":
        return cls(show_rule_under_title=bool(d["show_rule_under_title"]), fields=list(d["fields"]))


@dataclass
class FooterStyle:
    show_page_number: bool
    text: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "FooterStyle":
        return cls(show_page_number=bool(d["show_page_number"]), text=d.get("text", ""))


@dataclass
class CodeStyle:
    """Governs pandoc's own ``Source Code`` (paragraph)/``Verbatim Char``
    (character) docx styles for fenced code blocks/inline code -- see
    ``build_template.py``'s ``_style_source_code()``. Without this,
    pandoc's docx writer falls back to its own built-in defaults (Consolas
    11pt, ``#F1F3F5`` background, no padding) since quartifyr's
    reference-doc doesn't otherwise define those two style names.
    """

    font_size: float
    background_color: str
    padding_pt: float

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "CodeStyle":
        return cls(
            font_size=_require_positive(d["font_size"], "code.font_size"),
            background_color=_require_hex(d["background_color"], "code.background_color"),
            # Applied as paragraph space-before/after around the shaded
            # code block -- OOXML paragraph shading has no horizontal-
            # padding concept, so this is vertical spacing only, not true
            # CSS box padding.
            padding_pt=_require_nonnegative(d["padding_pt"], "code.padding_pt"),
        )


@dataclass
class EquationStyle:
    """Governs the docx-wide default math font (``word/settings.xml``'s
    ``m:mathPr/m:mathFont``) applied post-render by ``layout.py`` --
    pandoc's docx writer doesn't carry this setting through from a
    reference-doc, so it can't be set in ``build_template.py`` (see that
    module's own note). Font family only: an OOXML math run with no
    explicit run properties inherits its *size* from the surrounding
    paragraph, so there's no separate equation font size to configure.
    """

    font: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "EquationStyle":
        font = d["font"]
        if not isinstance(font, str) or not font:
            raise StyleConfigError(f"equation.font must be a non-empty string, got: {font!r}")
        return cls(font=font)


@dataclass
class Identity:
    org_name: str
    logo_path: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Identity":
        return cls(org_name=d.get("org_name", ""), logo_path=d.get("logo_path", ""))


@dataclass
class StyleConfig:
    fonts: Fonts
    colors: Colors
    page: Page
    paragraph: ParagraphStyle
    heading: HeadingStyle
    table: TableStyle
    synopsis: SynopsisStyle
    title_page: TitlePageStyle
    footer: FooterStyle
    code: CodeStyle
    equation: EquationStyle
    identity: Identity

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "StyleConfig":
        try:
            return cls(
                fonts=Fonts.from_dict(d["fonts"]),
                colors=Colors.from_dict(d["colors"]),
                page=Page.from_dict(d["page"]),
                paragraph=ParagraphStyle.from_dict(d["paragraph"]),
                heading=HeadingStyle.from_dict(d["heading"]),
                table=TableStyle.from_dict(d["table"]),
                synopsis=SynopsisStyle.from_dict(d["synopsis"]),
                title_page=TitlePageStyle.from_dict(d["title_page"]),
                footer=FooterStyle.from_dict(d["footer"]),
                code=CodeStyle.from_dict(d["code"]),
                equation=EquationStyle.from_dict(d["equation"]),
                identity=Identity.from_dict(d.get("identity", {})),
            )
        except KeyError as exc:
            raise StyleConfigError(f"style YAML is missing required key: {exc}") from exc

    @classmethod
    def load(cls, base_path: str | Path, override_path: str | Path | None = None) -> "StyleConfig":
        base_dict = yaml.safe_load(Path(base_path).read_text(encoding="utf-8"))
        if override_path is not None:
            override_dict = yaml.safe_load(Path(override_path).read_text(encoding="utf-8"))
            base_dict = deep_merge(base_dict, override_dict)
        return cls.from_dict(base_dict)
