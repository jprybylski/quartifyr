from pathlib import Path

import docx
import pytest
from docx.enum.text import WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from lxml import etree

from quartifyr_styling.layout import (
    LayoutError,
    apply_layout,
    apply_layout_from_qmd,
    read_qmd_frontmatter,
    resolve_confidential_label,
    resolve_header_left_text,
)


def test_read_qmd_frontmatter_parses_yaml_block(tmp_path):
    qmd = tmp_path / "report.qmd"
    qmd.write_text("---\ntitle: Foo\nproject: ACME-001\n---\n\nBody.\n")
    fm = read_qmd_frontmatter(qmd)
    assert fm == {"title": "Foo", "project": "ACME-001"}


def test_read_qmd_frontmatter_no_frontmatter_returns_empty(tmp_path):
    qmd = tmp_path / "report.qmd"
    qmd.write_text("Just body, no frontmatter.\n")
    assert read_qmd_frontmatter(qmd) == {}


def test_resolve_header_left_text_none_when_no_header_format():
    assert resolve_header_left_text({}, "draft") is None


def test_resolve_header_left_text_substitutes_placeholders():
    fm = {"header-format": "{project} - {report_number}", "project": "ACME-001", "report_number": "RPT-1001"}
    assert resolve_header_left_text(fm, "draft") == "ACME-001 - RPT-1001"


def test_resolve_header_left_text_does_not_auto_append_status():
    # Status has its own always-shown zone on the right (see apply_layout),
    # so the left text is used verbatim -- no more auto-appending "—
    # DRAFT"/"— FINAL" the way a single-zone header used to.
    fm = {"header-format": "{project}", "project": "ACME-001"}
    assert resolve_header_left_text(fm, "draft") == "ACME-001"


def test_resolve_header_left_text_status_placeholder_available():
    fm = {"header-format": "{status}: {project}", "project": "ACME-001"}
    assert resolve_header_left_text(fm, "final") == "FINAL: ACME-001"


def test_resolve_header_left_text_missing_placeholder_raises_clear_error():
    fm = {"header-format": "{project} - {missing_field}", "project": "ACME-001"}
    with pytest.raises(LayoutError, match="missing_field"):
        resolve_header_left_text(fm, "draft")


def test_resolve_confidential_label_uses_confidentiality_field():
    fm = {"confidentiality": "Confidential — Do Not Distribute"}
    assert resolve_confidential_label(fm) == "Confidential — Do Not Distribute"


def test_resolve_confidential_label_blank_when_unset():
    assert resolve_confidential_label({}) == ""


W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def _add_page_field_run(paragraph) -> None:
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_end)


def _add_ref_field_run(paragraph, *, bookmark: str, hyperlink: bool, cached_text: str = "Figure 1") -> None:
    """Mirrors the exact 5-run ``begin/instrText/separate/result/end``
    ``REF <bookmark> \\h`` field group quarto-plus's ``crossref`` shortcode
    and this extension's own ``appendix_crossref`` both emit (as distinct
    sibling ``<w:r>`` elements, not merged into one -- load-bearing for
    ``_match_ref_field_run_group()``, which scans for that exact shape).
    """
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    run._r.append(fld_begin)

    run = paragraph.add_run()
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = f" REF {bookmark} \\h " if hyperlink else f" REF {bookmark} "
    run._r.append(instr)

    run = paragraph.add_run()
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    run._r.append(fld_sep)

    paragraph.add_run(cached_text)

    run = paragraph.add_run()
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_end)


def _add_bookmark(paragraph, *, bookmark_id: str, name: str) -> None:
    for el_xml in [
        f'<w:bookmarkStart xmlns:w="{W_NS[1:-1]}" w:id="{bookmark_id}" w:name="{name}"/>',
        f'<w:bookmarkEnd xmlns:w="{W_NS[1:-1]}" w:id="{bookmark_id}"/>',
    ]:
        paragraph._p.append(etree.fromstring(el_xml))


def _build_docx_with_bookmarks(path: Path, *, include_front_matter_bookmark: bool) -> None:
    """A minimal docx with a page-number footer (mirroring what
    styling/build_template.py's reference-doc produces) and
    quartifyr-body-start (and, unless disabled, quartifyr-front-matter-
    start) bookmarks, to exercise apply_layout() without needing a real
    Quarto render.
    """
    document = docx.Document()
    document.add_paragraph("Title page para")

    section = document.sections[0]
    section.footer.is_linked_to_previous = False
    _add_page_field_run(section.footer.paragraphs[0])

    if include_front_matter_bookmark:
        front_matter_p = document.add_paragraph()
        _add_bookmark(front_matter_p, bookmark_id="800002", name="quartifyr-front-matter-start")

    document.add_paragraph("Front matter para")

    body_start_p = document.add_paragraph()
    _add_bookmark(body_start_p, bookmark_id="800001", name="quartifyr-body-start")

    document.add_paragraph("Body para")
    document.save(str(path))


def test_apply_layout_sets_equation_font(tmp_path):
    # python-docx's own bundled default template already ships an
    # m:mathPr/m:mathFont (Cambria Math, confirmed directly) -- this
    # exercises the "already present, update in place" branch of
    # _set_equation_font(), the realistic case for a docx built on that
    # template (as quartifyr's own reference-doc is).
    docx_path = tmp_path / "test.docx"
    document = docx.Document()
    document.add_paragraph("Body para")
    document.save(str(docx_path))
    assert document.settings.element.find(qn("m:mathPr")) is not None, "test assumption: template ships m:mathPr"

    apply_layout(docx_path, equation_font="Courier New")

    document = docx.Document(str(docx_path))
    math_fonts = document.settings.element.findall(f".//{qn('m:mathFont')}")
    assert len(math_fonts) == 1
    assert math_fonts[0].get(qn("m:val")) == "Courier New"


def test_apply_layout_creates_equation_font_when_absent(tmp_path):
    docx_path = tmp_path / "test.docx"
    document = docx.Document()
    document.add_paragraph("Body para")
    document.settings.element.remove(document.settings.element.find(qn("m:mathPr")))
    document.save(str(docx_path))
    assert document.settings.element.find(qn("m:mathPr")) is None

    apply_layout(docx_path, equation_font="Courier New")

    document = docx.Document(str(docx_path))
    math_pr = document.settings.element.find(qn("m:mathPr"))
    assert math_pr is not None
    math_font = math_pr.find(qn("m:mathFont"))
    assert math_font is not None
    assert math_font.get(qn("m:val")) == "Courier New"


def test_apply_layout_leaves_equation_font_untouched_when_not_given(tmp_path):
    docx_path = tmp_path / "test.docx"
    document = docx.Document()
    document.add_paragraph("Body para")
    document.save(str(docx_path))

    apply_layout(docx_path)

    document = docx.Document(str(docx_path))
    math_font = document.settings.element.find(qn("m:mathPr")).find(qn("m:mathFont"))
    assert math_font.get(qn("m:val")) == "Cambria Math"


def test_apply_layout_three_sections_with_title_page_bookmark(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_bookmarks(docx_path, include_front_matter_bookmark=True)

    apply_layout(
        docx_path,
        header_left_text="ACME-001 - RPT-1001",
        status="draft",
        confidential_label="Confidential",
    )

    result = docx.Document(str(docx_path))
    assert len(result.sections) == 3
    title, front_matter, body = result.sections

    for section in (title, front_matter, body):
        assert section.header.paragraphs[0].text == "ACME-001 - RPT-1001\tDRAFT"

    # Title page: confidential label + roman numeral, starting at "i".
    assert title.footer.paragraphs[0].text == "Confidential\t1"
    assert "PAGE" in title.footer.paragraphs[0]._p.xml
    title_pg_num_type = title._sectPr.find(qn("w:pgNumType"))
    assert title_pg_num_type is not None
    assert title_pg_num_type.get(qn("w:start")) == "1"
    assert title_pg_num_type.get(qn("w:fmt")) == "lowerRoman"

    # Rest of front matter: same roman sequence, continuing at "ii".
    assert front_matter.footer.paragraphs[0].text == "Confidential\t1"
    assert "PAGE" in front_matter.footer.paragraphs[0]._p.xml
    front_matter_pg_num_type = front_matter._sectPr.find(qn("w:pgNumType"))
    assert front_matter_pg_num_type is not None
    assert front_matter_pg_num_type.get(qn("w:start")) == "2"
    assert front_matter_pg_num_type.get(qn("w:fmt")) == "lowerRoman"

    # Body: confidential label + arabic, restarting at 1.
    assert body.footer.paragraphs[0].text == "Confidential\t1"
    assert "PAGE" in body.footer.paragraphs[0]._p.xml
    body_pg_num_type = body._sectPr.find(qn("w:pgNumType"))
    assert body_pg_num_type is not None
    assert body_pg_num_type.get(qn("w:start")) == "1"
    assert body_pg_num_type.get(qn("w:fmt")) == "decimal"


def test_apply_layout_two_sections_without_title_page_bookmark(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_bookmarks(docx_path, include_front_matter_bookmark=False)

    apply_layout(docx_path, header_left_text="ACME-001 - RPT-1001", status="draft")

    result = docx.Document(str(docx_path))
    assert len(result.sections) == 2
    front_matter, body = result.sections

    assert front_matter.header.paragraphs[0].text == "ACME-001 - RPT-1001\tDRAFT"
    assert body.header.paragraphs[0].text == "ACME-001 - RPT-1001\tDRAFT"

    # No title-page bookmark found: front matter as a whole gets no page number.
    assert "PAGE" not in front_matter.footer.paragraphs[0]._p.xml
    assert "PAGE" in body.footer.paragraphs[0]._p.xml

    body_pg_num_type = body._sectPr.find(qn("w:pgNumType"))
    assert body_pg_num_type is not None
    assert body_pg_num_type.get(qn("w:start")) == "1"


def test_apply_layout_without_bookmarks_is_single_section(tmp_path):
    docx_path = tmp_path / "no_bookmark.docx"
    document = docx.Document()
    document.add_paragraph("Just one section.")
    document.save(str(docx_path))

    apply_layout(docx_path, header_left_text="Header Text", status="final")

    result = docx.Document(str(docx_path))
    assert len(result.sections) == 1
    assert result.sections[0].header.paragraphs[0].text == "Header Text\tFINAL"


def test_apply_layout_nests_pandoc_header_id_bookmarks(tmp_path):
    # Mirrors issue #64: pandoc's docx writer emits a heading's auto
    # header-id bookmark (e.g. "section-b") as a bookmarkEnd/bookmarkStart
    # pair that are direct w:body children -- siblings of the surrounding
    # paragraphs, not nested inside one -- whenever nothing but a blank
    # markdown line separates the previous block from the next heading.
    # Right after a magic-string figure placeholder, that stray pair lands
    # between it and the image drawing reportifyr expects next, and
    # reportifyr's check_alt_text_magic_string crashes trying to
    # `.xpath()` the un-nested bookmark element (a plain lxml element
    # python-docx has no registered class for) with
    # "XPathEvalError: Undefined namespace prefix".
    docx_path = tmp_path / "header_id_bookmark.docx"
    document = docx.Document()
    document.add_paragraph("Intro")
    magic_p = document.add_paragraph("{rpfy}:example.png")
    body = document.element.body
    sectPr = body.find(qn("w:sectPr"))
    insert_at = list(body).index(sectPr)
    for el_xml in [
        f'<w:bookmarkEnd xmlns:w="{W_NS[1:-1]}" w:id="9"/>',
        f'<w:bookmarkStart xmlns:w="{W_NS[1:-1]}" w:id="10" w:name="section-b"/>',
    ]:
        body.insert(insert_at, etree.fromstring(el_xml))
        insert_at += 1
    document.add_paragraph("Section B")
    document.save(str(docx_path))

    body_children = list(docx.Document(str(docx_path)).element.body)
    assert any(el.tag == qn("w:bookmarkStart") for el in body_children), "test assumption: stray bookmark present"

    apply_layout(docx_path)

    result_body = docx.Document(str(docx_path)).element.body
    body_children = list(result_body)
    assert not any(el.tag in (qn("w:bookmarkStart"), qn("w:bookmarkEnd")) for el in body_children)

    magic_idx = next(i for i, el in enumerate(body_children) if el.tag == qn("w:p") and "example.png" in (el.text or "".join(t.text or "" for t in el.xpath(".//w:t"))))
    next_p = body_children[magic_idx + 1]
    assert next_p.tag == qn("w:p")
    assert "Section B" in "".join(t.text or "" for t in next_p.xpath(".//w:t"))

    # The bookmark itself survived, just nested -- not dropped.
    bookmark_starts = result_body.findall(f".//{qn('w:bookmarkStart')}")
    assert any(b.get(qn("w:name")) == "section-b" for b in bookmark_starts)


def test_apply_layout_missing_file_raises():
    with pytest.raises(FileNotFoundError):
        apply_layout("/does/not/exist.docx", header_left_text="x")


def _build_docx_with_crossref(path: Path) -> None:
    document = docx.Document()
    p = document.add_paragraph("See ")
    _add_ref_field_run(p, bookmark="Figure1", hyperlink=True)
    _add_page_field_run(document.sections[0].footer.paragraphs[0])
    document.save(str(path))


def _ref_instr_text(document) -> str:
    for instr in document.element.body.iter(qn("w:instrText")):
        if instr.text and "REF" in instr.text:
            return instr.text
    raise AssertionError("no REF field found")


def test_apply_layout_keeps_crossref_hyperlink_by_default(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    apply_layout(docx_path, header_left_text="Header")

    result = docx.Document(str(docx_path))
    assert "\\h" in _ref_instr_text(result)


def test_apply_layout_strips_crossref_hyperlink_when_disabled(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    apply_layout(docx_path, header_left_text="Header", crossref_hyperlinks=False)

    result = docx.Document(str(docx_path))
    text = _ref_instr_text(result)
    assert "\\h" not in text
    assert "REF Figure1" in text
    # PAGE fields are untouched -- only REF fields' \h switch is stripped.
    assert "PAGE" in result.sections[0].footer.paragraphs[0]._p.xml


def test_apply_layout_from_qmd_reads_crossref_hyperlinks_frontmatter(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    qmd_path = tmp_path / "report.qmd"
    qmd_path.write_text("---\ntitle: Foo\ncrossref-hyperlinks: false\n---\n\nBody.\n")

    apply_layout_from_qmd(docx_path, qmd_path, status="draft")

    result = docx.Document(str(docx_path))
    assert "\\h" not in _ref_instr_text(result)


def test_apply_layout_rejects_unrecognized_crossref_hyperlinks_value(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    with pytest.raises(LayoutError, match="crossref-hyperlinks"):
        apply_layout(docx_path, crossref_hyperlinks="every-other-tuesday")


def test_apply_layout_same_page_marks_ref_field_but_leaves_it_hyperlinked(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    apply_layout(docx_path, crossref_hyperlinks="same-page")

    result = docx.Document(str(docx_path))
    # The field itself is untouched -- still hyperlinked, the safe
    # fallback if same_page_crossrefs.resolve_same_page_crossrefs() never
    # runs against the filled document.
    assert "\\h" in _ref_instr_text(result)

    # A marker bookmark now sits immediately before the field, for that
    # later step to find.
    bookmark_names = [
        b.get(qn("w:name"))
        for b in result.element.body.iter(qn("w:bookmarkStart"))
        if b.get(qn("w:name"))
    ]
    assert any(name.startswith("quartifyr-crossref-target-") for name in bookmark_names)


def test_apply_layout_same_page_leaves_non_ref_fields_untouched(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    apply_layout(docx_path, crossref_hyperlinks="same-page")

    result = docx.Document(str(docx_path))
    assert "PAGE" in result.sections[0].footer.paragraphs[0]._p.xml
    assert result.sections[0].footer.paragraphs[0]._p.xml.count("PAGE") >= 1


def test_apply_layout_from_qmd_reads_same_page_crossref_hyperlinks(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_crossref(docx_path)

    qmd_path = tmp_path / "report.qmd"
    qmd_path.write_text('---\ntitle: Foo\ncrossref-hyperlinks: "same-page"\n---\n\nBody.\n')

    apply_layout_from_qmd(docx_path, qmd_path, status="draft")

    result = docx.Document(str(docx_path))
    bookmark_names = [
        b.get(qn("w:name"))
        for b in result.element.body.iter(qn("w:bookmarkStart"))
        if b.get(qn("w:name"))
    ]
    assert any(name.startswith("quartifyr-crossref-target-") for name in bookmark_names)


# --- landscape/portrait markers ---------------------------------------------


def _build_docx_with_orientation_markers(path: Path, markers: list[str], *, markers_before_body_start: bool = False) -> None:
    """Like ``_build_docx_with_bookmarks`` (with the title-page bookmark),
    plus one marker paragraph per entry in ``markers`` ("landscape"/
    "portrait") in the body, each followed by a content paragraph."""
    document = docx.Document()
    document.add_paragraph("Title page para")
    section = document.sections[0]
    section.footer.is_linked_to_previous = False
    _add_page_field_run(section.footer.paragraphs[0])
    _add_bookmark(document.add_paragraph(), bookmark_id="800002", name="quartifyr-front-matter-start")
    document.add_paragraph("Front matter para")
    if markers_before_body_start:
        _add_bookmark(document.add_paragraph(), bookmark_id="810001", name=f"quartifyr-{markers[0]}-1")
    _add_bookmark(document.add_paragraph(), bookmark_id="800001", name="quartifyr-body-start")
    document.add_paragraph("Body para")
    for n, orientation in enumerate(markers, start=1):
        if markers_before_body_start:
            break
        _add_bookmark(document.add_paragraph(), bookmark_id=str(810000 + n), name=f"quartifyr-{orientation}-{n}")
        document.add_paragraph(f"After marker {n}")
    document.save(str(path))


def _orientations(document) -> list[str]:
    return [
        "landscape" if s._sectPr.find(qn("w:pgSz")).get(qn("w:orient")) == "landscape" else "portrait"
        for s in document.sections
    ]


def test_landscape_then_portrait_marker_makes_a_landscape_section_between(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["landscape", "portrait"])

    apply_layout(docx_path, header_left_text="ACME-001", status="draft", confidential_label="Confidential")

    result = docx.Document(str(docx_path))
    # title, front matter, body, landscape, portrait again
    assert _orientations(result) == ["portrait", "portrait", "portrait", "landscape", "portrait"]
    portrait_width, portrait_height = result.sections[2].page_width, result.sections[2].page_height
    landscape = result.sections[3]
    assert landscape.page_width == portrait_height
    assert landscape.page_height == portrait_width
    assert result.sections[4].page_width == portrait_width


def test_trailing_landscape_does_not_turn_front_matter_or_body_landscape(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["landscape"])

    apply_layout(docx_path)

    result = docx.Document(str(docx_path))
    assert _orientations(result) == ["portrait", "portrait", "portrait", "landscape"]
    # The title page and front matter keep the portrait dimensions too, not just the attribute.
    for section in result.sections[:3]:
        assert section.page_width < section.page_height


def test_marker_sections_keep_headers_footers_and_page_number_continuity(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["landscape", "portrait"])

    apply_layout(docx_path, header_left_text="ACME-001", status="draft", confidential_label="Confidential")

    result = docx.Document(str(docx_path))
    landscape, portrait_again = result.sections[3], result.sections[4]
    for section in (landscape, portrait_again):
        assert section.header.paragraphs[0].text == "ACME-001\tDRAFT"
        assert section.footer.paragraphs[0].text == "Confidential\t1"
        assert "PAGE" in section.footer.paragraphs[0]._p.xml
        # No restart: only the body's first section sets pgNumType.
        assert section._sectPr.find(qn("w:pgNumType")) is None
    assert result.sections[2]._sectPr.find(qn("w:pgNumType")).get(qn("w:start")) == "1"

    # The right-aligned tab sits at each section's own content width.
    def right_tab(section) -> int:
        (tab,) = [t for t in section.footer.paragraphs[0].paragraph_format.tab_stops if t.alignment == WD_TAB_ALIGNMENT.RIGHT]
        return tab.position

    assert right_tab(landscape) == landscape.page_width - landscape.left_margin - landscape.right_margin
    assert right_tab(portrait_again) == portrait_again.page_width - portrait_again.left_margin - portrait_again.right_margin
    assert right_tab(landscape) > right_tab(portrait_again)
    # And they do not share a part with the portrait sections.
    assert landscape.footer._element is not result.sections[2].footer._element


def test_repeated_marker_adds_no_extra_break(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["portrait", "landscape", "landscape", "portrait"])

    apply_layout(docx_path)

    result = docx.Document(str(docx_path))
    assert _orientations(result) == ["portrait", "portrait", "portrait", "landscape", "portrait"]


def test_second_landscape_block_gets_its_own_section(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["landscape", "portrait", "landscape", "portrait"])

    apply_layout(docx_path, header_left_text="ACME-001", status="draft")

    result = docx.Document(str(docx_path))
    assert _orientations(result) == ["portrait", "portrait", "portrait", "landscape", "portrait", "landscape", "portrait"]


def test_no_markers_keeps_the_final_orientation_for_every_break(tmp_path):
    # With no markers the whole document is one orientation, so the breaks
    # copy it as before (here a landscape document).
    docx_path = tmp_path / "test.docx"
    _build_docx_with_bookmarks(docx_path, include_front_matter_bookmark=True)
    document = docx.Document(str(docx_path))
    _set_orientation_for_test(document.sections[0], "landscape")
    document.save(str(docx_path))

    apply_layout(docx_path)

    assert _orientations(docx.Document(str(docx_path))) == ["landscape", "landscape", "landscape"]


def _set_orientation_for_test(section, orientation: str) -> None:
    from quartifyr_styling.layout import _set_page_orientation

    _set_page_orientation(section._sectPr, orientation)


def test_marker_before_body_start_is_an_error(tmp_path):
    docx_path = tmp_path / "test.docx"
    _build_docx_with_orientation_markers(docx_path, ["landscape"], markers_before_body_start=True)

    with pytest.raises(LayoutError, match="before .*body-start"):
        apply_layout(docx_path)


def test_marker_without_body_start_is_an_error(tmp_path):
    docx_path = tmp_path / "test.docx"
    document = docx.Document()
    _add_bookmark(document.add_paragraph(), bookmark_id="810001", name="quartifyr-landscape-1")
    document.save(str(docx_path))

    with pytest.raises(LayoutError, match="body-start"):
        apply_layout(docx_path)
