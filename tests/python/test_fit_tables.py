"""Tests for fit_tables: widths come from the table's own section, never below the longest word."""

import zipfile
from pathlib import Path

import docx
import pytest
from docx.oxml import parse_xml
from docx.oxml.ns import qn
from lxml import etree

from quartifyr_styling import fit_tables as ft
from quartifyr_styling.fit_tables import FitTablesError, fit_tables

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'

NCA_HEADERS = [
    "Dose (mg)", "AUCinf", "AUClast", "Cmax", "Tmax", "CL/F", "V/F",
    "Half-life", "Kel", "MRT", "Accumulation", "Cmin", "Cavg", "Fluctuation",
]


def _cell(text: str, *, size_half_points: int = 20, bold: bool = False) -> str:
    bold_xml = '<w:b w:val="true"/>' if bold else ""
    rpr = (
        '<w:rFonts w:ascii="Arial Narrow" w:hAnsi="Arial Narrow"/>'
        f"{bold_xml}"
        f'<w:sz w:val="{size_half_points}"/><w:szCs w:val="{size_half_points}"/>'
    )
    return (
        "<w:tc><w:tcPr><w:tcMar>"
        '<w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/>'
        "</w:tcMar></w:tcPr>"
        f'<w:p><w:pPr><w:ind w:left="100" w:right="100"/><w:rPr>{rpr}</w:rPr></w:pPr>'
        f"<w:r><w:rPr>{rpr}</w:rPr><w:t>{text}</w:t></w:r></w:p></w:tc>"
    )


def _flextable_like(headers: list[str], rows: list[list[str]], *, name: str = "wide.csv", **cell_kwargs) -> str:
    """A table shaped like reportifyr's: autofit, 100% width, no grid, no cell widths, rpfy alt text."""
    header = "".join(_cell(h, bold=True, **cell_kwargs) for h in headers)
    body = "".join("<w:tr>" + "".join(_cell(v, **cell_kwargs) for v in row) + "</w:tr>" for row in rows)
    return (
        f"<w:tbl {W}><w:tblPr>"
        '<w:tblLayout w:type="autofit"/><w:jc w:val="center"/><w:tblW w:type="pct" w:w="5000"/>'
        '<w:tblLook w:firstRow="1"/>'
        f'<w:tblDescription w:val="{{rpfy}}:{name} [hash:abc]"/>'
        f"</w:tblPr><w:tr>{header}</w:tr>{body}</w:tbl>"
    )


def _lua_table() -> str:
    """Like the ones quartifyr's own filters emit: percentage widths, no rpfy alt text."""
    return (
        f'<w:tbl {W}><w:tblPr><w:tblW w:w="5000" w:type="pct"/></w:tblPr><w:tblGrid><w:gridCol/><w:gridCol/></w:tblGrid>'
        '<w:tr><w:tc><w:tcPr><w:tcW w:w="1500" w:type="pct"/></w:tcPr><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="3500" w:type="pct"/></w:tcPr><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    )


def _build(path: Path, *blocks: str) -> Path:
    """A docx whose body holds ``blocks`` in order. A block ``"LANDSCAPE_END"`` is an empty paragraph
    carrying a landscape sectPr (it ends a landscape section); ``"PORTRAIT_END"`` likewise portrait."""
    document = docx.Document()
    body = document.element.body
    final = body.find(qn("w:sectPr"))
    for side in ("left", "right"):
        final.find(qn("w:pgMar")).set(qn(f"w:{side}"), "1440")  # 1 in; python-docx's template uses 1.25 in
    portrait_w, portrait_h = final.find(qn("w:pgSz")).get(qn("w:w")), final.find(qn("w:pgSz")).get(qn("w:h"))
    for block in blocks:
        if block in ("LANDSCAPE_END", "PORTRAIT_END"):
            sect = parse_xml(
                f'<w:sectPr {W}>'
                + (
                    f'<w:pgSz w:w="{portrait_h}" w:h="{portrait_w}" w:orient="landscape"/>'
                    if block == "LANDSCAPE_END"
                    else f'<w:pgSz w:w="{portrait_w}" w:h="{portrait_h}"/>'
                )
                + '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
                "</w:sectPr>"
            )
            p = parse_xml(f"<w:p {W}><w:pPr/></w:p>")
            p.find(qn("w:pPr")).append(sect)
            final.addprevious(p)
        else:
            final.addprevious(parse_xml(block))
    document.save(str(path))
    return path


def _tables(path: Path) -> list:
    document = docx.Document(str(path))
    return list(document.element.body.iter(qn("w:tbl")))


def _grid(tbl) -> list[int]:
    return [int(g.get(qn("w:w"))) for g in tbl.findall(f"{qn('w:tblGrid')}/{qn('w:gridCol')}")]


def _longest_word_twips(tbl, col: int) -> int:
    """The widest word in the column, by the module's own estimate, with no padding."""
    widest = 0.0
    for tr in tbl.findall(qn("w:tr")):
        tc = tr.findall(qn("w:tc"))[col]
        for line in ft._cell_lines(tc, 0.0):
            word = 0.0
            for char, width in line:
                if char.isspace():
                    widest, word = max(widest, word), 0.0
                else:
                    word += width
            widest = max(widest, word)
    return int(widest * 20)


ROWS = [["10", "123.45", "99.9", "1.5", "0.5", "2.2", "30.1", "4.5", "0.1", "6.0", "1.2", "0.2", "0.9", "1.1"]]


def test_wide_table_columns_are_at_least_as_wide_as_the_longest_word_in_portrait(tmp_path):
    path = _build(tmp_path / "t.docx", _flextable_like(NCA_HEADERS, ROWS))

    result = fit_tables(path)

    (tbl,) = _tables(path)
    grid = _grid(tbl)
    assert result.fitted == 1 and result.overflowing == []
    assert len(grid) == 14
    for col, width in enumerate(grid):
        assert width >= _longest_word_twips(tbl, col), f"column {col} ({NCA_HEADERS[col]}) is narrower than its longest word"
    # The widest word is "Accumulation" / "Fluctuation": that column is wider than the dose column.
    assert grid[NCA_HEADERS.index("Accumulation")] > grid[NCA_HEADERS.index("Kel")]


def test_table_width_is_the_section_content_width(tmp_path):
    path = _build(tmp_path / "t.docx", _flextable_like(NCA_HEADERS, ROWS))
    content = 12240 - 2 * 1440

    fit_tables(path)

    (tbl,) = _tables(path)
    assert sum(_grid(tbl)) == content
    assert tbl.find(f"{qn('w:tblPr')}/{qn('w:tblW')}").get(qn("w:w")) == str(content)
    assert tbl.find(f"{qn('w:tblPr')}/{qn('w:tblW')}").get(qn("w:type")) == "dxa"
    assert tbl.find(f"{qn('w:tblPr')}/{qn('w:tblLayout')}").get(qn("w:type")) == "fixed"
    # Every cell's own width agrees with the grid.
    for tr in tbl.findall(qn("w:tr")):
        widths = [int(tc.find(f"{qn('w:tcPr')}/{qn('w:tcW')}").get(qn("w:w"))) for tc in tr.findall(qn("w:tc"))]
        assert widths == _grid(tbl)


def test_table_on_a_landscape_page_uses_the_landscape_width_and_the_next_portrait_one_its_own(tmp_path):
    path = _build(
        tmp_path / "t.docx",
        _flextable_like(NCA_HEADERS, ROWS, name="portrait-a.csv"),
        "PORTRAIT_END",
        _flextable_like(NCA_HEADERS, ROWS, name="landscape-b.csv"),
        "LANDSCAPE_END",
        _flextable_like(NCA_HEADERS, ROWS, name="portrait-c.csv"),
    )

    result = fit_tables(path)

    first, second, third = _tables(path)
    assert result.fitted == 3
    assert sum(_grid(first)) == 12240 - 2 * 1440
    assert sum(_grid(second)) == 15840 - 2 * 1440
    assert sum(_grid(third)) == 12240 - 2 * 1440
    for col, width in enumerate(_grid(second)):
        assert width >= _longest_word_twips(second, col)
    # More room on the landscape page, so the font is not shrunk there.
    assert {el.get(qn("w:val")) for el in second.iter(qn("w:sz"))} == {"20"}


def test_font_is_reduced_in_steps_only_when_the_words_do_not_fit(tmp_path):
    # A column whose single word is wider than the page at 10 pt but fits at a smaller size.
    long_words = [["Pharmacokinetic"] * 7]
    headers = ["Parameterization"] * 7
    path = _build(tmp_path / "t.docx", _flextable_like(headers, long_words))

    result = fit_tables(path)

    (tbl,) = _tables(path)
    sizes = {int(el.get(qn("w:val"))) for el in tbl.iter(qn("w:sz"))}
    assert result.shrunk == [1] and result.overflowing == []
    assert len(sizes) == 1
    (size,) = sizes
    assert 14 <= size < 20  # smaller than 10 pt, not below the 7 pt minimum
    assert {int(el.get(qn("w:val"))) for el in tbl.iter(qn("w:szCs"))} == {size}
    assert sum(_grid(tbl)) == 9360
    for col, width in enumerate(_grid(tbl)):
        assert width >= _longest_word_twips(tbl, col)


def test_font_is_not_reduced_when_the_words_fit(tmp_path):
    path = _build(tmp_path / "t.docx", _flextable_like(NCA_HEADERS[:6], [ROWS[0][:6]]))

    result = fit_tables(path)

    (tbl,) = _tables(path)
    assert result.shrunk == []
    assert {el.get(qn("w:val")) for el in tbl.iter(qn("w:sz"))} == {"20"}


def test_fourteen_columns_in_portrait_shrink_the_font_a_little_and_keep_every_word_whole(tmp_path):
    path = _build(tmp_path / "t.docx", _flextable_like(NCA_HEADERS, ROWS))

    result = fit_tables(path)

    (tbl,) = _tables(path)
    sizes = {int(el.get(qn("w:val"))) for el in tbl.iter(qn("w:sz"))}
    assert result.shrunk == [1] and result.overflowing == []
    assert sizes == {16}  # 10 pt -> 8 pt, in 1 pt steps, above the 7 pt minimum


def test_a_table_that_cannot_fit_even_at_the_minimum_size_is_reported_and_still_fitted_to_the_page(tmp_path):
    headers = [f"Supercalifragilistic{i}" for i in range(10)]
    path = _build(tmp_path / "t.docx", _flextable_like(headers, [["1"] * 10]))

    result = fit_tables(path)

    (tbl,) = _tables(path)
    assert result.overflowing == [1] and result.shrunk == [1]
    assert sum(_grid(tbl)) == 9360  # still no wider than the page
    assert {int(el.get(qn("w:val"))) for el in tbl.iter(qn("w:sz"))} == {14}  # the 7 pt minimum


def test_other_tables_are_left_alone(tmp_path):
    path = _build(tmp_path / "t.docx", _lua_table(), _flextable_like(NCA_HEADERS, ROWS))
    before = etree_string(_tables(path)[0])

    result = fit_tables(path)

    lua, _ = _tables(path)
    assert result.fitted == 1
    assert etree_string(lua) == before


def etree_string(element) -> str:
    return etree.tostring(element).decode()


def test_a_docx_without_reportifyr_tables_is_not_rewritten(tmp_path):
    path = _build(tmp_path / "t.docx", _lua_table())
    before = path.read_bytes()

    result = fit_tables(path)

    assert result.fitted == 0
    assert path.read_bytes() == before


def test_other_package_parts_are_copied_through_unchanged(tmp_path):
    path = _build(tmp_path / "t.docx", _flextable_like(NCA_HEADERS, ROWS))
    with zipfile.ZipFile(path) as z:
        before = {n: z.read(n) for n in z.namelist() if n != "word/document.xml"}

    fit_tables(path)

    with zipfile.ZipFile(path) as z:
        after = {n: z.read(n) for n in z.namelist() if n != "word/document.xml"}
    assert after == before
    assert docx.Document(str(path)).element.body is not None  # still opens


def test_merged_header_cell_takes_the_width_of_the_columns_it_spans(tmp_path):
    table = _flextable_like(["A", "B", "C"], [["1", "2", "3"]])
    document_table = parse_xml(table)
    first_row = document_table.findall(qn("w:tr"))[0]
    cells = first_row.findall(qn("w:tc"))
    first_row.remove(cells[2])
    span = parse_xml(f'<w:gridSpan {W} w:val="2"/>')
    cells[1].find(qn("w:tcPr")).append(span)
    path = _build(tmp_path / "t.docx", etree_string(document_table))

    fit_tables(path)

    (tbl,) = _tables(path)
    grid = _grid(tbl)
    assert len(grid) == 3
    header = tbl.findall(qn("w:tr"))[0].findall(qn("w:tc"))
    assert [int(tc.find(f"{qn('w:tcPr')}/{qn('w:tcW')}").get(qn("w:w"))) for tc in header] == [grid[0], grid[1] + grid[2]]


def test_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        fit_tables(tmp_path / "nope.docx")


def test_not_a_docx_raises_a_clear_error(tmp_path):
    bad = tmp_path / "bad.docx"
    bad.write_text("not a zip")
    with pytest.raises(FitTablesError, match="not a readable docx"):
        fit_tables(bad)
