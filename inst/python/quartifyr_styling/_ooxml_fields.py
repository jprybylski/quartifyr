"""Shared low-level helpers for locating and editing this project's ``REF``
cross-reference field OOXML.

Used by both ``layout.py`` (``crossref-hyperlinks: false`` -- strip every
``\\h`` document-wide -- and ``"same-page"`` -- mark each field for later
resolution) and ``same_page_crossrefs.py`` (the post-pass-2 step that
resolves those marks into a final hyperlinked/not decision). Factored out
rather than duplicated since both need to recognize the exact same
``REF <bookmark> [\\h]`` field shape -- whether emitted by quarto-plus's
``crossref`` shortcode or this extension's own ``appendix_crossref``.
"""

from __future__ import annotations

import re

from docx.oxml.ns import qn

REF_FIELD_INSTR_RE = re.compile(r"^\s*REF\s+(\S+)\s*(?:\\h\s*)?$")
REF_FIELD_HYPERLINK_SWITCH_RE = re.compile(r"^(\s*REF\s+\S+\s*)\\h(\s*)$")

# Bookmark naming for crossref-hyperlinks: "same-page" markers (see
# layout.py's _mark_crossrefs_for_same_page_resolution() and
# same_page_crossrefs.py). The w:id range is offset well clear of
# quarto-plus's own crossref.lua (starts at 1, increments per caption) and
# this extension's appendix.lua (reserves 900000+) so bookmark w:id values
# can never collide within the same document.
SAME_PAGE_MARKER_PREFIX = "quartifyr-crossref-target-"
SAME_PAGE_MARKER_ID_BASE = 950000


def match_ref_field_run_group(runs: list, i: int) -> tuple[str, str] | None:
    """If ``runs[i:i+5]`` is the ``begin/instrText/separate/result/end`` run
    group of a ``REF <bookmark>`` field, with or without ``\\h``, returns
    ``(bookmark, cached_result_text)``; otherwise ``None``.
    """
    if i + 5 > len(runs):
        return None
    fld_begin = runs[i].find(qn("w:fldChar"))
    instr = runs[i + 1].find(qn("w:instrText"))
    fld_sep = runs[i + 2].find(qn("w:fldChar"))
    fld_end = runs[i + 4].find(qn("w:fldChar"))
    if (
        fld_begin is None
        or fld_begin.get(qn("w:fldCharType")) != "begin"
        or instr is None
        or not instr.text
        or fld_sep is None
        or fld_sep.get(qn("w:fldCharType")) != "separate"
        or fld_end is None
        or fld_end.get(qn("w:fldCharType")) != "end"
    ):
        return None
    match = REF_FIELD_INSTR_RE.match(instr.text)
    if not match:
        return None
    cached_run = runs[i + 3].find(qn("w:t"))
    return match.group(1), (cached_run.text if cached_run is not None and cached_run.text else "")


def find_bookmark_paragraph(document, name: str):
    """Returns the ``<w:p>`` containing a ``w:bookmarkStart`` named ``name``,
    or ``None``. Shared by ``layout.py`` (``quartifyr-front-matter-start``/
    ``quartifyr-body-start``) and ``_caption_lists.py``
    (``quartifyr-list-of-figures``/``quartifyr-list-of-tables``) -- every
    marker bookmark this project's Lua filters leave for a later
    post-render step to find again.
    """
    body = document.element.body
    for p in body.iter(qn("w:p")):
        for bookmark in p.iter(qn("w:bookmarkStart")):
            if bookmark.get(qn("w:name")) == name:
                return p
    return None


def strip_hyperlink_switch(instr_text_element) -> bool:
    """If ``instr_text_element`` is a ``REF <bookmark> \\h`` field's
    instruction text, removes the ``\\h`` switch in place and returns
    ``True``; otherwise leaves it untouched and returns ``False``.
    """
    text = instr_text_element.text
    if not text:
        return False
    match = REF_FIELD_HYPERLINK_SWITCH_RE.match(text)
    if not match:
        return False
    instr_text_element.text = match.group(1).rstrip() + match.group(2)
    return True
