"""Shared helper for inserting a ``word/settings.xml`` (``CT_Settings``)
child element at a schema-correct position.

Used by ``build_template.py`` (``w:updateFields``) and ``layout.py``
(``m:mathPr``) -- both need to add an element ECMA-376 requires to appear
in a specific sequence among whatever settings the document already has,
without assuming which of its neighbors are present.
"""

from __future__ import annotations

from docx.oxml.ns import qn

# CT_Settings's schema (ECMA-376) tag sequence, starting right after
# `w:updateFields` -- copied from python-docx's own
# `docx.oxml.settings.CT_Settings._tag_seq` (not importable: that module
# deletes the name off the class after using it internally). Covers every
# element quartifyr currently needs to position relative to
# (`w:updateFields`, `m:mathPr`), not the full schema.
TAIL_ORDER_AFTER_UPDATE_FIELDS = (
    "w:hdrShapeDefaults",
    "w:footnotePr",
    "w:endnotePr",
    "w:compat",
    "w:docVars",
    "w:rsids",
    "m:mathPr",
    "w:attachedSchema",
    "w:themeFontLang",
    "w:clrSchemeMapping",
    "w:doNotIncludeSubdocsInStats",
    "w:doNotAutoCompressPictures",
    "w:forceUpgrade",
    "w:captions",
    "w:readModeInkLockDown",
    "w:smartTagType",
    "sl:schemaLibrary",
    "w:shapeDefaults",
    "w:doNotEmbedSmartTags",
    "w:decimalSymbol",
    "w:listSeparator",
)


def insert_settings_child(settings_element, new_child, *, after_tag: str | None = None) -> None:
    """Inserts ``new_child`` into ``settings_element`` at the position
    ECMA-376 requires for the tag named ``after_tag`` (which must appear
    in ``TAIL_ORDER_AFTER_UPDATE_FIELDS``), regardless of which of its
    schema neighbors ``settings_element`` currently has. ``after_tag=None``
    (default) positions ``new_child`` as ``w:updateFields`` itself would
    sit -- before every tag in ``TAIL_ORDER_AFTER_UPDATE_FIELDS``.

    Finds the first existing child whose tag comes *after* ``after_tag``
    in the schema sequence and inserts immediately before it; if none of
    those later tags are present, appends to the end.
    """
    if after_tag is None:
        later_tags = TAIL_ORDER_AFTER_UPDATE_FIELDS
    else:
        later_tags = TAIL_ORDER_AFTER_UPDATE_FIELDS[TAIL_ORDER_AFTER_UPDATE_FIELDS.index(after_tag) + 1 :]
    successor = next(
        (child for child in settings_element if child.tag in {qn(tag) for tag in later_tags}),
        None,
    )
    if successor is not None:
        successor.addprevious(new_child)
    else:
        settings_element.append(new_child)
