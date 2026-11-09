"""Post-pass-2 table fitting: give every reportifyr table the width of its page.

``reportifyr::build_report()`` formats a CSV/RDS table with a flextable that
is autofit at 100% width (``w:tblLayout autofit``, ``w:tblW 100%``, no grid
and no cell widths) and leaves the column widths to the word processor. With
a dozen or more columns (NCA parameters, say) that gives columns a few
characters wide and header words that break mid-word, and the result differs
between Word and LibreOffice. This step rewrites each such table with an
explicit fixed layout instead:

- The available width is the **content width of the section the table is
  in** (page width minus margins), so a table on a ``{{< landscape >}}`` page
  uses the landscape width, never a fixed 6 inches.
- Every column is at least as wide as its longest unbreakable word (plus the
  cell's own padding), so a word is never split. The rest of the width is
  shared out in proportion to how much room each column's content wants.
- When even the floors don't fit the section, the font size is reduced in
  1 pt steps (never below ``MIN_FONT_PT``, 7 pt; runs already smaller are
  left alone) until they do. Header text wraps at word boundaries as usual.
- If the floors still don't fit at ``MIN_FONT_PT``, the table is fitted to
  the page anyway (so it cannot run off it) and reported in
  ``FitTablesResult.overflowing``: a word may then break.

Only tables reportifyr inserted are touched: they carry an alt-text
(``w:tblDescription``) starting with ``{rpfy}:``, which ``build_report()``
stamps on every filled placeholder. The tables quartifyr's own filters
generate (title page, signatures, synopsis) are percentage-width already and
are left alone.

Widths are *estimated*: no font files are assumed, so the width of a word is
computed from Helvetica/Arial character metrics, scaled for bold (x1.06) and
for condensed families such as Arial Narrow (x0.9, wider than their true
ratio on purpose, since a substituted font is usually wider). The estimate
errs wide; a column may end up slightly roomier than strictly needed, never
narrower than the longest word.

The edit is made directly on ``word/document.xml`` and every other part of
the package is copied through unchanged.
"""

from __future__ import annotations

import math
import os
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from lxml import etree

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
_NS = {"w": W_NS}

MIN_FONT_PT = 7.0
"""The smallest font size a table is shrunk to (points)."""

FONT_STEP_PT = 1.0
RPFY_MARKER = "{rpfy}:"

_DEFAULT_FONT_PT = 10.0
_DEFAULT_CELL_MARGIN_TWIPS = 108  # Word's built-in default left/right cell margin
_BORDER_ALLOWANCE_TWIPS = 20  # a cell's own left/right borders, per cell
_DEFAULT_PAGE_WIDTH_TWIPS = 12240
_DEFAULT_MARGIN_TWIPS = 1440
_BOLD_FACTOR = 1.06
_CONDENSED_FACTOR = 0.9

# Helvetica/Arial advance widths in 1/1000 em for printable ASCII (from 0x20).
_ASCII_WIDTHS = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,  # space ! " # $ % & ' ( ) * + , - . /
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556,  # 0-9
    278, 278, 584, 584, 584, 556, 1015,  # : ; < = > ? @
    667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611,  # A-Z
    278, 278, 278, 469, 556, 333,  # [ \ ] ^ _ `
    556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500,  # a-z
    334, 260, 334, 584,  # { | } ~
]
_DEFAULT_CHAR_WIDTH = 556


class FitTablesError(RuntimeError):
    """Raised when fitting the tables of a docx fails."""


@dataclass
class FitTablesResult:
    """What ``fit_tables()`` did. Indexes count reportifyr tables in document order (from 1)."""

    path: Path
    fitted: int = 0
    shrunk: list[int] = field(default_factory=list)
    overflowing: list[int] = field(default_factory=list)


def _w(tag: str) -> str:
    return f"{{{W_NS}}}{tag}"


def _int_attr(element, attr: str, default: int | None = None) -> int | None:
    if element is None:
        return default
    value = element.get(_w(attr))
    try:
        return int(value) if value is not None else default
    except ValueError:
        return default


def _section_content_width(sectPr) -> int:
    """Page width minus left/right margins and gutter, in twips."""
    pg_sz = sectPr.find("w:pgSz", _NS) if sectPr is not None else None
    pg_mar = sectPr.find("w:pgMar", _NS) if sectPr is not None else None
    page = _int_attr(pg_sz, "w", _DEFAULT_PAGE_WIDTH_TWIPS)
    left = _int_attr(pg_mar, "left", _DEFAULT_MARGIN_TWIPS)
    right = _int_attr(pg_mar, "right", _DEFAULT_MARGIN_TWIPS)
    gutter = _int_attr(pg_mar, "gutter", 0)
    return page - left - right - gutter


def _first(parent, *tags: str):
    """The first of ``parent``'s ``w:<tag>`` children that exists, or ``None``.

    (Not ``a or b``: an lxml element with no children is falsy.)
    """
    for tag in tags:
        element = parent.find(f"w:{tag}", _NS)
        if element is not None:
            return element
    return None


def _is_rpfy_table(tbl) -> bool:
    description = tbl.find("w:tblPr/w:tblDescription", _NS)
    return description is not None and (description.get(_w("val")) or "").startswith(RPFY_MARKER)


def _tables_with_content_width(body) -> list[tuple[object, int]]:
    """Each top-level table with the content width of the section it is in.

    A ``sectPr`` inside a paragraph's ``pPr`` ends a section, and the body's
    own trailing ``sectPr`` describes the last one, so a table belongs to the
    first section end that comes after it.
    """
    result: list[tuple[object, int]] = []
    pending: list[object] = []
    for child in body:
        if child.tag == _w("tbl"):
            pending.append(child)
        elif child.tag == _w("p"):
            sectPr = child.find("w:pPr/w:sectPr", _NS)
            if sectPr is not None:
                width = _section_content_width(sectPr)
                result.extend((tbl, width) for tbl in pending)
                pending = []
        elif child.tag == _w("sectPr"):
            width = _section_content_width(child)
            result.extend((tbl, width) for tbl in pending)
            pending = []
    # No trailing sectPr at all (not a real Word document): the defaults.
    result.extend((tbl, _section_content_width(None)) for tbl in pending)
    return result


def _char_width(char: str) -> int:
    code = ord(char)
    if 32 <= code <= 126:
        return _ASCII_WIDTHS[code - 32]
    return _DEFAULT_CHAR_WIDTH


def _run_style(run, paragraph_rpr) -> tuple[float, bool, float, bool]:
    """``(size_pt, bold, width_factor, size_is_explicit)`` for a run, falling back to the paragraph mark's
    properties. A size that isn't written anywhere (so can't be reduced) is assumed to be 10 pt."""

    def lookup(tag: str):
        for rpr in (run.find("w:rPr", _NS), paragraph_rpr):
            if rpr is not None:
                element = rpr.find(f"w:{tag}", _NS)
                if element is not None:
                    return element
        return None

    size = lookup("sz")
    size_pt = _int_attr(size, "val", None)
    explicit = bool(size_pt)
    size_pt = size_pt / 2 if size_pt else _DEFAULT_FONT_PT

    bold_el = lookup("b")
    bold = bold_el is not None and (bold_el.get(_w("val")) or "true").lower() not in ("false", "0", "off")

    fonts = lookup("rFonts")
    name = ""
    if fonts is not None:
        name = (fonts.get(_w("ascii")) or fonts.get(_w("hAnsi")) or "").lower()
    factor = _CONDENSED_FACTOR if ("narrow" in name or "condensed" in name) else 1.0
    return size_pt, bold, factor, explicit


def _cell_lines(tc, font_delta_pt: float) -> list[list[tuple[str, float]]]:
    """The cell's text as lines (one per paragraph and per ``w:br``), each a list of ``(char, width_pt)``."""
    lines: list[list[tuple[str, float]]] = []
    for paragraph in tc.findall("w:p", _NS):
        paragraph_rpr = paragraph.find("w:pPr/w:rPr", _NS)
        line: list[tuple[str, float]] = []
        for run in paragraph.iter(_w("r")):
            size_pt, bold, factor, explicit = _run_style(run, paragraph_rpr)
            if explicit and size_pt > MIN_FONT_PT:
                size_pt = max(size_pt - font_delta_pt, MIN_FONT_PT)
            scale = size_pt / 1000 * factor * (_BOLD_FACTOR if bold else 1.0)
            for node in run:
                if node.tag == _w("t") and node.text:
                    line.extend((char, _char_width(char) * scale) for char in node.text)
                elif node.tag == _w("tab"):
                    line.append((" ", _char_width(" ") * scale))
                elif node.tag in (_w("br"), _w("cr")):
                    lines.append(line)
                    line = []
        lines.append(line)
    return lines


def _horizontal_padding_twips(tc, tbl_cell_margin: tuple[int, int]) -> int:
    """Cell margins + paragraph indents + a border allowance, in twips."""
    margins = tc.find("w:tcPr/w:tcMar", _NS)
    if margins is not None:
        left = _int_attr(_first(margins, "left", "start"), "w", tbl_cell_margin[0])
        right = _int_attr(_first(margins, "right", "end"), "w", tbl_cell_margin[1])
    else:
        left, right = tbl_cell_margin
    indent = 0
    for ind in tc.iterfind("w:p/w:pPr/w:ind", _NS):
        indent = max(
            indent,
            (_int_attr(ind, "left", None) or _int_attr(ind, "start", 0) or 0)
            + (_int_attr(ind, "right", None) or _int_attr(ind, "end", 0) or 0),
        )
    return left + right + indent + _BORDER_ALLOWANCE_TWIPS


def _table_cell_margin(tbl) -> tuple[int, int]:
    margins = tbl.find("w:tblPr/w:tblCellMar", _NS)
    if margins is None:
        return (_DEFAULT_CELL_MARGIN_TWIPS, _DEFAULT_CELL_MARGIN_TWIPS)
    left = _int_attr(_first(margins, "left", "start"), "w", _DEFAULT_CELL_MARGIN_TWIPS)
    right = _int_attr(_first(margins, "right", "end"), "w", _DEFAULT_CELL_MARGIN_TWIPS)
    return (left, right)


def _row_cells(tbl) -> list[list[tuple[object, int, int]]]:
    """Per row, ``(tc, first_column_index, gridSpan)`` for each cell."""
    rows = []
    for tr in tbl.findall("w:tr", _NS):
        column = 0
        cells = []
        for tc in tr.findall("w:tc", _NS):
            span = _int_attr(tc.find("w:tcPr/w:gridSpan", _NS), "val", 1) or 1
            cells.append((tc, column, span))
            column += span
        rows.append(cells)
    return rows


def _column_metrics(rows, n_columns: int, font_delta_pt: float, tbl_cell_margin) -> tuple[list[int], list[int]]:
    """``(floors, naturals)`` per column, in twips.

    The floor is the longest unbreakable word plus padding, the natural width
    is the longest single line plus padding. Cells that span several columns
    don't contribute: they take whatever their columns add up to.
    """
    floors = [0] * n_columns
    naturals = [0] * n_columns
    for cells in rows:
        for tc, column, span in cells:
            if span != 1:
                continue
            padding = _horizontal_padding_twips(tc, tbl_cell_margin)
            longest_word = 0.0
            longest_line = 0.0
            for line in _cell_lines(tc, font_delta_pt):
                longest_line = max(longest_line, sum(width for _, width in line))
                word = 0.0
                for char, width in line:
                    if char.isspace():
                        longest_word = max(longest_word, word)
                        word = 0.0
                    else:
                        word += width
                longest_word = max(longest_word, word)
            floors[column] = max(floors[column], math.ceil(longest_word * 20) + padding)
            naturals[column] = max(naturals[column], math.ceil(longest_line * 20) + padding)
    # A column no single cell covers (all spans) still needs a width.
    for index in range(n_columns):
        if floors[index] == 0:
            floors[index] = 2 * _DEFAULT_CELL_MARGIN_TWIPS
        naturals[index] = max(naturals[index], floors[index])
    return floors, naturals


def _distribute(floors: list[int], naturals: list[int], available: int) -> list[int]:
    """Column widths summing to ``available``, none below its floor (when the floors fit)."""
    total_floor, total_natural = sum(floors), sum(naturals)
    if total_floor >= available:
        # Cannot honour the floors: scale them down to fit the page.
        scale = available / total_floor
        widths = [int(f * scale) for f in floors]
    elif total_natural <= available:
        # Everything fits on one line: share the spare width out by content.
        spare = available - total_natural
        widths = [n + int(spare * n / total_natural) for n in naturals]
    else:
        # Between the floors and the natural widths: each column gets its
        # floor plus the same fraction of what it would like beyond that.
        fraction = (available - total_floor) / (total_natural - total_floor)
        widths = [f + int((n - f) * fraction) for f, n in zip(floors, naturals)]
    widths[-1] += available - sum(widths)  # rounding remainder
    return widths


def _set_font_delta(tbl, delta_pt: float) -> None:
    """Lowers every run's (and paragraph mark's) size by ``delta_pt``, not below ``MIN_FONT_PT``."""
    if delta_pt <= 0:
        return
    half_points = round(delta_pt * 2)
    minimum = round(MIN_FONT_PT * 2)
    for tag in ("sz", "szCs"):
        for element in tbl.iter(_w(tag)):
            current = _int_attr(element, "val", None)
            if current is not None and current > minimum:
                element.set(_w("val"), str(max(current - half_points, minimum)))


def _child(parent, tag: str, *, before: tuple[str, ...] = ()):
    """The ``w:<tag>`` child of ``parent``, created (before the first ``before`` sibling, else appended)."""
    element = parent.find(f"w:{tag}", _NS)
    if element is not None:
        return element
    element = etree.Element(_w(tag))
    for sibling_tag in before:
        sibling = parent.find(f"w:{sibling_tag}", _NS)
        if sibling is not None:
            sibling.addprevious(element)
            return element
    parent.append(element)
    return element


def _write_widths(tbl, rows, widths: list[int], available: int) -> None:
    tbl_pr = tbl.find("w:tblPr", _NS)
    if tbl_pr is None:
        tbl_pr = etree.Element(_w("tblPr"))
        tbl.insert(0, tbl_pr)

    tbl_w = _child(tbl_pr, "tblW", before=("jc", "tblCellSpacing", "tblInd", "tblBorders", "shd", "tblLayout", "tblCellMar", "tblLook"))
    tbl_w.set(_w("type"), "dxa")
    tbl_w.set(_w("w"), str(available))
    layout = _child(tbl_pr, "tblLayout", before=("tblCellMar", "tblLook", "tblCaption", "tblDescription"))
    layout.set(_w("type"), "fixed")

    grid = tbl.find("w:tblGrid", _NS)
    if grid is None:
        grid = etree.Element(_w("tblGrid"))
        tbl_pr.addnext(grid)
    for old in list(grid):
        grid.remove(old)
    for width in widths:
        etree.SubElement(grid, _w("gridCol")).set(_w("w"), str(width))

    for cells in rows:
        for tc, column, span in cells:
            tc_pr = tc.find("w:tcPr", _NS)
            if tc_pr is None:
                tc_pr = etree.Element(_w("tcPr"))
                tc.insert(0, tc_pr)
            tc_w = tc_pr.find("w:tcW", _NS)
            if tc_w is None:
                tc_w = etree.Element(_w("tcW"))
                cnf = tc_pr.find("w:cnfStyle", _NS)
                if cnf is not None:
                    cnf.addnext(tc_w)
                else:
                    tc_pr.insert(0, tc_w)
            tc_w.set(_w("type"), "dxa")
            tc_w.set(_w("w"), str(sum(widths[column : column + span])))


def _fit_table(tbl, available: int) -> tuple[bool, bool]:
    """Fits one table; returns ``(shrunk, overflowing)``."""
    rows = _row_cells(tbl)
    n_columns = max((sum(span for _, _, span in cells) for cells in rows), default=0)
    if n_columns == 0:
        return False, False
    tbl_cell_margin = _table_cell_margin(tbl)

    # Every explicit size is lowered by the same delta (not below MIN_FONT_PT),
    # so nothing can shrink further once the largest size is at the minimum.
    largest = _largest_font_pt(tbl) or _DEFAULT_FONT_PT
    max_delta = max(largest - MIN_FONT_PT, 0.0)
    delta = 0.0
    floors, naturals = _column_metrics(rows, n_columns, delta, tbl_cell_margin)
    while sum(floors) > available and delta < max_delta:
        delta = min(delta + FONT_STEP_PT, max_delta)
        floors, naturals = _column_metrics(rows, n_columns, delta, tbl_cell_margin)

    overflowing = sum(floors) > available
    widths = _distribute(floors, naturals, available)
    _set_font_delta(tbl, delta)
    _write_widths(tbl, rows, widths, available)
    return delta > 0, overflowing


def _largest_font_pt(tbl) -> float | None:
    sizes = [_int_attr(el, "val", None) for el in tbl.iter(_w("sz"))]
    sizes = [size for size in sizes if size]
    return max(sizes) / 2 if sizes else None


def fit_tables(docx_path: str | Path) -> FitTablesResult:
    """Fits every reportifyr table in ``docx_path`` to its section's width, in place."""
    docx_path = Path(docx_path)
    if not docx_path.exists():
        raise FileNotFoundError(f"docx not found: {docx_path}")

    try:
        with zipfile.ZipFile(docx_path) as archive:
            document_xml = archive.read("word/document.xml")
    except (zipfile.BadZipFile, KeyError) as exc:
        raise FitTablesError(f"{docx_path}: not a readable docx ({exc})") from exc

    root = etree.fromstring(document_xml)
    body = root.find("w:body", _NS)
    result = FitTablesResult(path=docx_path)
    if body is None:
        return result

    index = 0
    for tbl, available in _tables_with_content_width(body):
        if not _is_rpfy_table(tbl):
            continue
        index += 1
        shrunk, overflowing = _fit_table(tbl, available)
        result.fitted += 1
        if shrunk:
            result.shrunk.append(index)
        if overflowing:
            result.overflowing.append(index)

    if result.fitted == 0:
        return result

    new_xml = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
    _replace_document_xml(docx_path, new_xml)
    return result


def _replace_document_xml(docx_path: Path, new_xml: bytes) -> None:
    """Rewrites the package with ``word/document.xml`` replaced; every other entry is copied as it is."""
    fd, tmp_name = tempfile.mkstemp(suffix=".docx", dir=str(docx_path.parent))
    os.close(fd)
    tmp_path = Path(tmp_name)
    try:
        with zipfile.ZipFile(docx_path) as source, zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as target:
            for item in source.infolist():
                data = new_xml if item.filename == "word/document.xml" else source.read(item.filename)
                target.writestr(item, data)
        os.replace(tmp_path, docx_path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise
