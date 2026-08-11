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
--
-- Contributors (authors/reviewers) each get a 3-row signature block: a
-- blank signature line, printed name, and title stacked in the left
-- column, with a vertically-merged Role label ("Author"/"Reviewer") beside
-- the block. Approvers get a 2-row block (signature line, name) since
-- their role is already implied by the "Approvers" heading -- the slot
-- that would otherwise say "Role" instead carries their actual job title,
-- which is what a reader wants to know for an approval signature.
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

local function signature_line_cell(width)
  return string.format(
    [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>
        <w:p>
          <w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="000000"/></w:pBdr><w:spacing w:before="360"/></w:pPr>
        </w:p>
      </w:tc>
  ]],
    width
  )
end

local function text_cell(width, text, italic)
  local run_props = ""
  if italic then
    run_props = "<w:rPr><w:i/></w:rPr>"
  end
  return string.format(
    [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>
        <w:p><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>
      </w:tc>
  ]],
    width,
    run_props,
    utils.escape_xml(text)
  )
end

local function side_label_cell(width, text, vmerge_val)
  local vmerge = string.format('<w:vMerge w:val="%s"/>', vmerge_val)
  if vmerge_val == "continue" then
    vmerge = "<w:vMerge/>"
  end
  if text == nil then
    return string.format(
      [[
      <w:tc>
        <w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s</w:tcPr>
        <w:p/>
      </w:tc>
  ]],
      width,
      vmerge
    )
  end
  return string.format(
    [[
      <w:tc>
        <w:tcPr>
          <w:tcW w:w="%d" w:type="dxa"/>
          %s
          <w:vAlign w:val="center"/>
        </w:tcPr>
        <w:p>
          <w:pPr><w:jc w:val="center"/></w:pPr>
          <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>
        </w:p>
      </w:tc>
  ]],
    width,
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
      <w:tblW w:w="0" w:type="auto"/>
      <w:tblLook w:val="04A0" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
    </w:tblPr>
    <w:tblGrid>
      <w:gridCol w:w="6000"/>
      <w:gridCol w:w="2000"/>
    </w:tblGrid>
]]
local TABLE_CLOSE = [[
  </w:tbl>
  <w:p/>
]]

-- 3-row block: [signature | Role], [name | ], [title | ]  (Role spans all 3 rows)
local function contributor_block(name, title, role_label)
  local rows = {}
  table.insert(rows, "<w:tr>" .. signature_line_cell(6000) .. side_label_cell(2000, role_label, "restart") .. "</w:tr>")
  table.insert(rows, "<w:tr>" .. text_cell(6000, name, false) .. side_label_cell(2000, nil, "continue") .. "</w:tr>")
  table.insert(rows, "<w:tr>" .. text_cell(6000, title, true) .. side_label_cell(2000, nil, "continue") .. "</w:tr>")
  return TABLE_OPEN .. table.concat(rows, "\n") .. TABLE_CLOSE
end

-- 2-row block: [signature | Title], [name | ]  (Title spans both rows)
local function approver_block(name, title)
  local rows = {}
  table.insert(rows, "<w:tr>" .. signature_line_cell(6000) .. side_label_cell(2000, title, "restart") .. "</w:tr>")
  table.insert(rows, "<w:tr>" .. text_cell(6000, name, false) .. side_label_cell(2000, nil, "continue") .. "</w:tr>")
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
