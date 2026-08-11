-- Builds "Contributors" and "Approvers" signature pages from YAML
-- frontmatter and inserts them right after the title page.
--
-- Frontmatter contract:
--
--   contributors:
--     authors:
--       - name: "Jane Doe, PharmD"
--         title: "Lead Scientist"
--     reviewers:
--       - name: "John Smith, PhD"
--         title: "Senior Biostatistician"
--   approvers:
--     - name: "Alice Lee, MD"
--       title: "Medical Director"
--   signature-mode: "line"   # default; or "note"
--   signature-note: "Approved electronically in the XYZ system"  # used when signature-mode: "note"
--
-- Contributors (authors/reviewers) each get a 3-row signature block: a
-- blank signing space, printed name, and title stacked in the left
-- column, with a vertically-merged Role label ("Author"/"Reviewer") beside
-- the block. Approvers get a 2-row block (signing space, name) since
-- their role is already implied by the "Approvers" heading -- the slot
-- that would otherwise say "Role" instead carries their actual job title,
-- which is what a reader wants to know for an approval signature.
--
-- The signing-space row is deliberately just an empty, tall cell -- no
-- internal rule/line -- the table's own bordered cell already reads as
-- "sign here" and an extra line inside it doubled up visually. When
-- physical/wet signatures aren't the workflow (e.g. a validated
-- e-signature system), set `signature-mode: "note"` to replace that empty
-- space with a short note (`signature-note:`) instead, applied uniformly
-- to every contributor/approver block.
--
-- Table widths are percentage-based (w:type="pct"), not fixed twips, so
-- they genuinely span the *current* usable text width regardless of the
-- page margins configured in the docx reference-doc (see
-- styling/styles/*.yaml's page.margins_in) -- a fixed-twips table sized
-- for one org's margins would come up short or overflow under another's.
--
-- NOTE ON FILTER ORDER: like title_page.lua, this filter prepends its
-- content at the very front of the document (position 1). Because both
-- filters use that same simple pattern, whichever one's Pandoc stage runs
-- *last* ends up visually first. _extension.yml lists
-- `[signature_page.lua, title_page.lua]` -- signature_page runs first
-- (pushing itself to the front), then title_page runs and pushes itself
-- in front of that, yielding the correct final order: title page, then
-- signature pages, then the rest of the document.

local utils = require("utils")

local CONTRIBUTOR_GROUPS = {
  { key = "authors", label = "Author" },
  { key = "reviewers", label = "Reviewer" },
}

-- Percent-of-table widths (fiftieths of a percent; 5000 = 100%).
local LABEL_PCT = 3750 -- 75%
local ROLE_PCT = 1250 -- 25%

local function stringify_or_nil(meta_val)
  if meta_val == nil then
    return nil
  end
  local s = pandoc.utils.stringify(meta_val)
  if s == "" then
    return nil
  end
  return s
end

local function parse_people(entries)
  local people = {}
  if not entries then
    return people
  end
  for _, entry in ipairs(entries) do
    local name = stringify_or_nil(entry.name)
    local title = stringify_or_nil(entry.title)
    if name then
      table.insert(people, { name = name, title = title or "" })
    end
  end
  return people
end

-- group_key -> {label=, people={{name=, title=}, ...}}
local contributor_groups = {}
-- list of {name=, title=}
local approvers = {}
local signature_mode = "line" -- or "note"
local signature_note = ""

local function heading_paragraph(text)
  -- Prepend a real tab character to match quarto-plus's header.lua
  -- indentation of authored Markdown headings (it can't see this
  -- raw-openxml heading to indent it itself, since it only walks typed
  -- Header AST nodes). NOTE: `\t` has no special meaning inside a Lua
  -- `[[ ]]` long-bracket string -- it would be the literal two characters
  -- `\` and `t` -- so the tab has to come from a normal quoted string.
  local tab_char = "\t"
  -- pStyle must reference the style ID ("Heading1", no space), not the
  -- display name ("Heading 1", with a space) -- the display name renders
  -- visually fine but Word's ToC field silently fails to recognize the
  -- paragraph as a heading at all, confirmed via a real Word
  -- field-recalculation test (Contributors/Approvers were missing from a
  -- real, recalculated ToC despite looking correctly styled).
  return string.format(
    [[
  <w:p>
    <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
    <w:r><w:t xml:space="preserve">%s%s</w:t></w:r>
  </w:p>
  ]],
    tab_char,
    utils.escape_xml(text)
  )
end

-- The "space to sign" cell: either a tall empty cell (signature_mode ==
-- "line") or the configured note text (signature_mode == "note").
local function signing_space_cell(pct)
  if signature_mode == "note" and signature_note ~= "" then
    return string.format(
      [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/><w:vAlign w:val="center"/></w:tcPr>
        <w:p><w:r><w:rPr><w:i/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
  ]],
      pct,
      utils.escape_xml(signature_note)
    )
  end
  return string.format(
    [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        <w:p/>
      </w:tc>
  ]],
    pct
  )
end

local function text_cell(pct, text, italic)
  local run_props = ""
  if italic then
    run_props = "<w:rPr><w:i/></w:rPr>"
  end
  return string.format(
    [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/></w:tcPr>
        <w:p><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
  ]],
    pct,
    run_props,
    utils.escape_xml(text)
  )
end

local function side_label_cell(pct, text, vmerge_val)
  local vmerge = string.format('<w:vMerge w:val="%s"/>', vmerge_val)
  if vmerge_val == "continue" then
    vmerge = "<w:vMerge/>"
  end
  if text == nil then
    return string.format(
      [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="pct"/>%s</w:tcPr>
        <w:p/>
      </w:tc>
  ]],
      pct,
      vmerge
    )
  end
  return string.format(
    [[
      <w:tc>
        <w:tcPr>
          <w:tcW w:w="%d" w:type="pct"/>
          %s
          <w:vAlign w:val="center"/>
        </w:tcPr>
        <w:p>
          <w:pPr><w:jc w:val="center"/></w:pPr>
          <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>
        </w:p>
      </w:tc>
  ]],
    pct,
    vmerge,
    utils.escape_xml(text)
  )
end

-- tblStyle references the style ID ("TableGrid"), not the display name
-- ("Table Grid") -- same pStyle-vs-styleId pitfall as heading_paragraph()
-- above; a wrong reference here just silently drops our reference-doc's
-- customized borders/header shading rather than breaking a Word feature
-- outright, so it's easier to miss without specifically checking for it.
local TABLE_OPEN = [[
  <w:tbl>
    <w:tblPr>
      <w:tblStyle w:val="TableGrid"/>
      <w:tblW w:w="5000" w:type="pct"/>
      <w:tblLook w:val="04A0" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
    </w:tblPr>
    <w:tblGrid>
      <w:gridCol/>
      <w:gridCol/>
    </w:tblGrid>
]]
local TABLE_CLOSE = [[
  </w:tbl>
  <w:p/>
]]

-- Enough room to actually pen a signature (or read a note comfortably),
-- rather than a default-height row that reads as accidentally blank.
local SIGNING_ROW = [[<w:trPr><w:trHeight w:val="720" w:hRule="atLeast"/></w:trPr>]]

-- 3-row block: [signing space | Role], [name | ], [title | ]  (Role spans all 3 rows)
local function contributor_block(name, title, role_label)
  local rows = {}
  table.insert(
    rows,
    "<w:tr>" .. SIGNING_ROW .. signing_space_cell(LABEL_PCT) .. side_label_cell(ROLE_PCT, role_label, "restart") .. "</w:tr>"
  )
  table.insert(rows, "<w:tr>" .. text_cell(LABEL_PCT, name, false) .. side_label_cell(ROLE_PCT, nil, "continue") .. "</w:tr>")
  table.insert(rows, "<w:tr>" .. text_cell(LABEL_PCT, title, true) .. side_label_cell(ROLE_PCT, nil, "continue") .. "</w:tr>")
  return TABLE_OPEN .. table.concat(rows, "\n") .. TABLE_CLOSE
end

-- 2-row block: [signing space | Title], [name | ]  (Title spans both rows)
local function approver_block(name, title)
  local rows = {}
  table.insert(
    rows,
    "<w:tr>" .. SIGNING_ROW .. signing_space_cell(LABEL_PCT) .. side_label_cell(ROLE_PCT, title, "restart") .. "</w:tr>"
  )
  table.insert(rows, "<w:tr>" .. text_cell(LABEL_PCT, name, false) .. side_label_cell(ROLE_PCT, nil, "continue") .. "</w:tr>")
  return TABLE_OPEN .. table.concat(rows, "\n") .. TABLE_CLOSE
end

return {
  {
    Meta = function(meta)
      local contributors = meta["contributors"]
      if contributors then
        for _, group in ipairs(CONTRIBUTOR_GROUPS) do
          local people = parse_people(contributors[group.key])
          if #people > 0 then
            contributor_groups[group.key] = { label = group.label, people = people }
          end
        end
      end

      approvers = parse_people(meta["approvers"])

      local mode = stringify_or_nil(meta["signature-mode"])
      if mode == "note" then
        signature_mode = "note"
      end
      signature_note = stringify_or_nil(meta["signature-note"]) or ""

      return meta
    end,
  },
  {
    Pandoc = function(doc)
      local parts = {}

      local has_contributors = false
      for _, group in ipairs(CONTRIBUTOR_GROUPS) do
        if contributor_groups[group.key] then
          has_contributors = true
          break
        end
      end

      if has_contributors then
        table.insert(parts, heading_paragraph("Contributors"))
        for _, group in ipairs(CONTRIBUTOR_GROUPS) do
          local g = contributor_groups[group.key]
          if g then
            for _, person in ipairs(g.people) do
              table.insert(parts, contributor_block(person.name, person.title, g.label))
            end
          end
        end
      end

      if #approvers > 0 then
        table.insert(parts, heading_paragraph("Approvers"))
        for _, person in ipairs(approvers) do
          table.insert(parts, approver_block(person.name, person.title))
        end
      end

      if #parts == 0 then
        return doc
      end

      table.insert(parts, [[<w:p><w:r><w:br w:type="page"/></w:r></w:p>]])

      local ooxml = table.concat(parts, "\n")
      table.insert(doc.blocks, 1, pandoc.RawBlock("openxml", ooxml))

      return doc
    end,
  },
}
