from pathlib import Path

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

from quartifyr_styling.build_template import build_reference_docx
from quartifyr_styling.schema import StyleConfig

DEFAULT_YAML = Path(__file__).parent.parent / "styles" / "default.yaml"
W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def _build(tmp_path, override=None):
    config = StyleConfig.load(DEFAULT_YAML, override)
    out = build_reference_docx(config, tmp_path / "reference.docx")
    return out, docx.Document(str(out))


def test_build_writes_file(tmp_path):
    out, doc = _build(tmp_path)
    assert out.exists()
    assert out.suffix == ".docx"


def test_default_preset_is_times_new_roman_and_black(tmp_path):
    _, doc = _build(tmp_path)
    for name in ["Normal", "Title", "Subtitle", "Heading 1", "Heading 4", "Caption"]:
        style = doc.styles[name]
        assert style.font.name == "Times New Roman", name
        assert str(style.font.color.rgb) == "000000", name


def test_no_theme_font_references_survive_on_styled_elements(tmp_path):
    # Regression test: python-docx's bundled default template gives Title/
    # Subtitle/Heading N BOTH a literal ascii font AND a *Theme reference
    # (asciiTheme="majorHAnsi" etc) on the same rFonts element. Word/
    # LibreOffice prefer the theme reference when both are present and
    # silently ignore the literal font -- font.name reads back correctly
    # via python-docx's API regardless, since that only reads the (ignored)
    # literal attribute, which is exactly how this shipped undetected:
    # headings rendered in the theme's major font (Calibri, falling back to
    # Arial where Calibri isn't installed) instead of Times New Roman.
    _, doc = _build(tmp_path)
    theme_attrs = (qn("w:asciiTheme"), qn("w:hAnsiTheme"), qn("w:cstheme"), qn("w:eastAsiaTheme"))
    for name in ["Normal", "Title", "Subtitle", "Heading 1", "Heading 4", "Caption", "TOC 1", "Footer"]:
        rfonts = doc.styles[name].element.find(f".//{W_NS}rFonts")
        assert rfonts is not None, name
        for attr in theme_attrs:
            assert rfonts.get(attr) is None, f"{name} still has theme font reference {attr}"


def test_heading_sizes_descend_with_level(tmp_path):
    _, doc = _build(tmp_path)
    sizes = [doc.styles[f"Heading {lvl}"].font.size.pt for lvl in (1, 2, 3, 4)]
    assert sizes == sorted(sizes, reverse=True)


def test_caption_is_italic_not_bold(tmp_path):
    _, doc = _build(tmp_path)
    caption = doc.styles["Caption"]
    assert caption.font.italic is True
    assert caption.font.bold is False


def test_logo_alignment_styles_present(tmp_path):
    _, doc = _build(tmp_path)
    assert doc.styles["Logo Left"].paragraph_format.alignment == WD_ALIGN_PARAGRAPH.LEFT
    assert doc.styles["Logo Right"].paragraph_format.alignment == WD_ALIGN_PARAGRAPH.RIGHT
    assert doc.styles["Subtitle"].paragraph_format.alignment == WD_ALIGN_PARAGRAPH.CENTER


def test_page_size_and_margins_applied(tmp_path):
    _, doc = _build(tmp_path)
    section = doc.sections[0]
    assert section.page_width.inches == 8.5
    assert section.page_height.inches == 11.0
    assert section.top_margin.inches == 1
    assert section.left_margin.inches == 1


def test_toc_styles_have_dot_leader_tab_stop(tmp_path):
    _, doc = _build(tmp_path)
    for level in (1, 2, 3):
        style = doc.styles[f"TOC {level}"]
        tab_stops = style.paragraph_format.tab_stops
        assert len(tab_stops) == 1
        assert str(tab_stops[0].leader).endswith("DOTS (4)") or "DOTS" in str(tab_stops[0].leader)


def test_table_grid_has_borders_and_header_shading(tmp_path):
    _, doc = _build(tmp_path)
    style_el = doc.styles["Table Grid"].element
    borders = style_el.find(f".//{W_NS}tblBorders")
    assert borders is not None
    assert len(borders.findall(f"{W_NS}top")) == 1

    first_row_pr = style_el.find(f'.//{W_NS}tblStylePr[@{W_NS}type="firstRow"]')
    assert first_row_pr is not None
    shading = first_row_pr.find(f".//{W_NS}shd")
    assert shading.get(qn("w:fill")) == "D9D9D9"


def test_bibliography_style_has_body_font_and_hanging_indent(tmp_path):
    # pandoc's docx writer applies pStyle "Bibliography" to each entry in a
    # citeproc-generated reference list; it isn't one of python-docx's
    # bundled built-in styles, so build_template.py has to add it.
    _, doc = _build(tmp_path)
    style = doc.styles["Bibliography"]
    assert style.font.name == "Times New Roman"
    assert str(style.font.color.rgb) == "000000"
    assert style.paragraph_format.left_indent.inches == 0.5
    assert style.paragraph_format.first_line_indent.inches == -0.5


def test_hyperlink_style_blends_in_with_body_text(tmp_path):
    # pandoc's citeproc output (link-citations: true) applies pStyle/rStyle
    # "Hyperlink" to each in-text citation. Deliberately styled to match
    # Normal body text (no blue, no underline) rather than a conventional
    # web-link look, matching how this extension's own REF-field crossrefs/
    # appendix_crossrefs render -- clickable but carrying no distinguishing
    # rStyle at all. Word treats "Hyperlink" as a reserved built-in ID and
    # renders *something* even if undefined, so it still has to be defined
    # explicitly here rather than left to an unverified fallback.
    _, doc = _build(tmp_path)
    style = doc.styles["Hyperlink"]
    assert style.font.underline is False
    assert str(style.font.color.rgb) == "000000"
    assert style.font.name == "Times New Roman"


def test_footer_has_page_number_field(tmp_path):
    _, doc = _build(tmp_path)
    footer_para = doc.sections[0].footer.paragraphs[0]
    xml = footer_para._p.xml
    assert "PAGE" in xml
    assert 'w:fldCharType="begin"' in xml
    assert 'w:fldCharType="end"' in xml


def test_settings_enable_update_fields_on_open(tmp_path):
    _, doc = _build(tmp_path)
    update_fields = doc.settings.element.find(qn("w:updateFields"))
    assert update_fields is not None
    assert update_fields.get(qn("w:val")) == "true"


def test_update_fields_inserted_at_schema_correct_position(tmp_path):
    # w:updateFields must come after w:savePreviewPicture and before
    # w:compat per CT_Settings' schema order -- appending blindly to the
    # end would land it after w:compat/w:rsids/etc, which real-world
    # bundled templates already contain.
    _, doc = _build(tmp_path)
    tags = [child.tag for child in doc.settings.element]
    assert qn("w:savePreviewPicture") in tags
    assert qn("w:compat") in tags
    assert tags.index(qn("w:savePreviewPicture")) < tags.index(qn("w:updateFields")) < tags.index(qn("w:compat"))


def test_org_override_changes_heading_color_and_body_font(tmp_path):
    override_path = tmp_path / "org.yaml"
    override_path.write_text(
        "colors:\n  heading: '#1A2B3C'\nfonts:\n  body: 'Georgia'\n"
    )
    _, doc = _build(tmp_path, override_path)
    assert doc.styles["Normal"].font.name == "Georgia"
    assert str(doc.styles["Heading 1"].font.color.rgb) == "1A2B3C"
    # Untouched styles keep the default preset.
    assert doc.styles["Title"].font.name == "Times New Roman"
