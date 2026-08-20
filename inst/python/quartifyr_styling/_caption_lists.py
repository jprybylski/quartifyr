"""Builds quartifyr's combined List of Figures/List of Tables, spanning
BOTH quarto-plus's own continuous ``fig_caption``/``tbl_caption`` and
this extension's six scoped caption shortcodes (``appendix_fig_caption``/
``appendix_tbl_caption``, ``section_fig_caption``/``section_tbl_caption``,
``subsection_fig_caption``/``subsection_tbl_caption`` --
``_extensions/quartifyr/appendix.lua``), in true document order.

WHY THIS IS A POST-RENDER PYTHON STEP, NOT A LUA FILTER: the natural first
approach was a `contributes: filters:` Lua filter (``caption_lists.lua``)
whose `Pandoc`-stage function walks the whole document once, collecting
every caption's bookmark/label/text, then fills in whichever
``.quartifyr_list_of_figures``/``.quartifyr_list_of_tables`` div it finds.
That doesn't work: confirmed empirically (rendering a real document and
inspecting ``doc.blocks`` from inside such a filter) that Quarto resolves
extension shortcodes -- quarto-plus's ``fig_caption``/``tbl_caption`` and
this extension's own six scoped ones alike -- in a pass that runs
strictly *after* every `contributes: filters:` Lua filter from every
extension has already finished, regardless of that filter's own position
in `_extension.yml`'s `filters:` list. A `Pandoc`-stage filter at that
point still sees each `{{< fig_caption ... >}}`/
`{{< appendix_fig_caption ... >}}` call unexpanded -- there's no
caption bookmark or `SEQ` field for it to find yet. So no Lua filter can
see the whole document's resolved caption set the way this feature needs
to.

``caption_lists.lua`` still runs as a Lua filter, but only for what Lua
*can* still do at that point: its `.quartifyr_list_of_figures`/
`.quartifyr_list_of_tables` placeholder divs are ordinary pandoc
fenced-div syntax, not a shortcode, so they're already real `Div` AST
nodes at filter time. It marks each one it finds with a small bookmark
(`quartifyr-list-of-figures`/`quartifyr-list-of-tables`) -- the same
"leave a findable marker for a later post-render step" trick
``title_page.lua``'s own `quartifyr-front-matter-start` bookmark already
uses for `layout.py`'s section-splitting. This module does the actual
work here, once Quarto's full render (shortcodes included) has produced a
real ``document.xml`` with every caption's bookmark/`SEQ` field genuinely
present -- the same "package-parts editing needs the finished docx"
reasoning `layout.py`'s own module docstring gives for the header/footer
split.

HOW EACH ENTRY IS BUILT: order and caption wording are read directly off
the rendered docx and copied verbatim -- safe because reportifyr's pass 2
only fills placeholder *content* into existing captions, it never adds,
removes, or reorders them, so the caption set/order here is already final.
The visible "Figure 3"/"Figure A1" number is a live ``REF bookmark \\h``
field reusing the original caption's own bookmark -- the same mechanism
`crossref`/`appendix_crossref`/`scoped_crossref` already use to resolve a
single reference. The page number is a live ``PAGEREF bookmark \\h``
field against that *same* bookmark: no new bookmark needed, since a
caption's own bookmark already marks its position on whatever page it
renders on. Both fields, plus the caption text between them, sit inside
one ``<w:hyperlink>`` per entry so the whole line is click-to-navigate,
styled with the reference-doc's existing "Hyperlink" character style.
Layout reuses the existing "TOC 1" paragraph style (its dot-leader,
right-aligned tab stop sized to the usable text width -- see
``build_template.py``'s ``_configure_toc_style``) applied directly via
``w:pStyle``, not through Word's own automatic TOC-field style-application
machinery: this is a plain hand-built paragraph, not a native TOC field,
so nothing here depends on Word ever recalculating *which* style an entry
gets -- only on recalculating the REF/PAGEREF field values themselves,
same as every other field this extension emits.

Each entry's cached (pre-recalculation) fallback text is deliberately
inexact -- "Figure ?" for the REF field, "?" for PAGEREF -- matching
`appendix_crossref`'s own "Appendix ?" precedent (`appendix.lua`) rather
than trying to precompute the real number/page here too. Both resolve to
the correct value on the next field recalculation, same as every other
field this extension emits.
"""

from __future__ import annotations

import re

from docx.oxml import OxmlElement
from docx.oxml.ns import qn

from ._ooxml_fields import find_bookmark_paragraph

LIST_OF_FIGURES_BOOKMARK = "quartifyr-list-of-figures"
LIST_OF_TABLES_BOOKMARK = "quartifyr-list-of-tables"

_CAPTION_SEQ_RE = re.compile(r"SEQ\s+(\w+)\s*\\\*\s*ARABIC")


def _match_caption_paragraph(p) -> dict | None:
    """If ``p`` is a caption paragraph -- quarto-plus's own continuous
    ``fig_caption``/``tbl_caption`` or one of this extension's six scoped
    caption shortcodes -- returns its ``{label, bookmark, caption_text}``;
    otherwise ``None``.

    Recognizes the bookmarkStart+SEQ...ARABIC+tab+caption shape common to
    both: each caption shortcode emits exactly one paragraph with this
    shape (confirmed against both `crossref.lua` and `appendix.lua`),
    differing only in which SEQ field name it uses (``Figure``/``Table``
    vs. ``AppendixFigure``/``AppendixTable``/``SectionFigure``/
    ``SectionTable``/``SubsectionFigure``/``SubsectionTable``). Doesn't
    match the `appendix` heading's own ``SEQ Appendix`` bookmark: no
    ``ARABIC`` switch there by default, and even under
    ``appendix-numbering: arabic`` its field name "Appendix" contains
    neither "Figure" nor "Table".
    """
    bookmark = None
    for bm in p.iter(qn("w:bookmarkStart")):
        bookmark = bm.get(qn("w:name"))
        break
    if bookmark is None:
        return None

    seq_field = None
    for instr in p.iter(qn("w:instrText")):
        if instr.text:
            match = _CAPTION_SEQ_RE.search(instr.text)
            if match:
                seq_field = match.group(1)
                break
    if seq_field is None:
        return None

    if "Figure" in seq_field:
        label = "Figure"
    elif "Table" in seq_field:
        label = "Table"
    else:
        return None

    # Text after the LAST w:tab in the paragraph (there's only ever one --
    # the tab that separates the number from the caption text -- but
    # taking the last is more robust than assuming that).
    caption_text = ""
    parts: list[str] = []
    for child in p.iter():
        if child.tag == qn("w:tab"):
            parts = []
        elif child.tag == qn("w:t"):
            parts.append(child.text or "")
    caption_text = "".join(parts)

    return {"label": label, "bookmark": bookmark, "caption_text": caption_text}


def collect_captions(document) -> tuple[list[dict], list[dict]]:
    """Walks the whole document body in order, returning
    ``(figures, tables)`` -- each a list of ``{label, bookmark,
    caption_text}`` entries in true document order.
    """
    figures: list[dict] = []
    tables: list[dict] = []
    for p in document.element.body.iter(qn("w:p")):
        entry = _match_caption_paragraph(p)
        if entry is None:
            continue
        (figures if entry["label"] == "Figure" else tables).append(entry)
    return figures, tables


def _field_runs(instr_text: str, *, cached_text: str, style: str) -> list:
    """Builds the five ``<w:r>`` elements of one field's begin/instrText/
    separate/result/end run group, each styled with character style
    ``style`` -- mirroring ``layout.py``'s own ``_add_page_field()``
    shape, plus an ``rStyle`` per run.
    """
    runs = []

    def _run_with(*children):
        r = OxmlElement("w:r")
        rpr = OxmlElement("w:rPr")
        rstyle = OxmlElement("w:rStyle")
        rstyle.set(qn("w:val"), style)
        rpr.append(rstyle)
        r.append(rpr)
        for child in children:
            r.append(child)
        runs.append(r)

    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    fld_begin.set(qn("w:dirty"), "true")
    _run_with(fld_begin)

    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = instr_text
    _run_with(instr)

    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    _run_with(fld_sep)

    result = OxmlElement("w:t")
    result.set(qn("xml:space"), "preserve")
    result.text = cached_text
    _run_with(result)

    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    _run_with(fld_end)

    return runs


def _text_run(text: str, *, style: str):
    r = OxmlElement("w:r")
    rpr = OxmlElement("w:rPr")
    rstyle = OxmlElement("w:rStyle")
    rstyle.set(qn("w:val"), style)
    rpr.append(rstyle)
    r.append(rpr)
    t = OxmlElement("w:t")
    t.set(qn("xml:space"), "preserve")
    t.text = text
    r.append(t)
    return r


def _tab_run(*, style: str):
    r = OxmlElement("w:r")
    rpr = OxmlElement("w:rPr")
    rstyle = OxmlElement("w:rStyle")
    rstyle.set(qn("w:val"), style)
    rpr.append(rstyle)
    r.append(rpr)
    r.append(OxmlElement("w:tab"))
    return r


def _build_entry_paragraph(entry: dict):
    p = OxmlElement("w:p")
    p_pr = OxmlElement("w:pPr")
    p_style = OxmlElement("w:pStyle")
    p_style.set(qn("w:val"), "TOC1")
    p_pr.append(p_style)
    p.append(p_pr)

    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("w:anchor"), entry["bookmark"])

    for r in _field_runs(f' REF {entry["bookmark"]} \\h ', cached_text=f'{entry["label"]} ?', style="Hyperlink"):
        hyperlink.append(r)
    hyperlink.append(_text_run(f' {entry["caption_text"]}', style="Hyperlink"))
    hyperlink.append(_tab_run(style="Hyperlink"))
    for r in _field_runs(f' PAGEREF {entry["bookmark"]} \\h ', cached_text="?", style="Hyperlink"):
        hyperlink.append(r)

    p.append(hyperlink)
    return p


def _fill_caption_list(document, bookmark_name: str, entries: list[dict]) -> None:
    marker_p = find_bookmark_paragraph(document, bookmark_name)
    if marker_p is None or not entries:
        # No `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables` div
        # in this project's shell .qmd (most projects), or that type has
        # no captions -- render nothing, same "toggle off when there's
        # nothing to show" behavior as synopsis.lua's own empty case.
        return
    anchor = marker_p
    for entry in entries:
        new_p = _build_entry_paragraph(entry)
        anchor.addnext(new_p)
        anchor = new_p


def build_caption_lists(document) -> None:
    """Fills in both `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables`
    marker bookmarks (if present -- most projects have neither) with a
    combined, hand-built List of Figures/List of Tables covering every
    caption in the document, in true document order.
    """
    figures, tables = collect_captions(document)
    _fill_caption_list(document, LIST_OF_FIGURES_BOOKMARK, figures)
    _fill_caption_list(document, LIST_OF_TABLES_BOOKMARK, tables)
