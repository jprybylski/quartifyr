-- Builds a fax-cover-sheet-style memo cover page (MEMORANDUM banner +
-- To/From/Date/Re/Cc grid) from YAML frontmatter, and prepends it as the
-- document's first page -- an alternative to title_page.lua's report
-- title page for memo-type documents, which typically want a looser
-- structure underneath (no ToC/List of Figures/List of Tables/
-- abbreviations required -- those are quarto-plus shortcode divs the
-- author simply omits from the body, not something this filter needs to
-- know about; see _extensions/quartifyr/README.md's "Memo cover page"
-- section).
--
-- Frontmatter contract:
--
--   memo:
--     to: "Jane Doe, CFO"
--     from: "John Smith, Controller"
--     date: "2026-08-12"
--     re: "Q3 Budget Review"
--     cc: "Finance Committee"        # optional
--   memo-heading: "MEMORANDUM"        # optional, default "MEMORANDUM"
--   document-status: "DRAFT"          # optional, default "DRAFT" -- same
--                                      # convention as title_page.lua
--
-- Activates only when `memo:` is present in frontmatter -- the same "own
-- your own frontmatter key, no-op if absent" convention every other
-- filter in this extension follows (title_page.lua on `title:`,
-- signature_page.lua on `contributors:`/`approvers:`). A real project
-- just never sets `title:` for a memo, so title_page.lua self-skips via
-- its own existing guard -- no separate `doc-type:` mode switch needed.
--
-- Unlike title_page.lua's Title paragraph (which needs an invisible
-- tiny-heading trick to give the ToC a "Title Page" entry independent of
-- the real, different title text -- see title_page.lua's file-header
-- comment), the MEMORANDUM banner here is a single, real, VISIBLE
-- Heading1 paragraph: its ToC-entry text and its on-page text are the
-- same string, so there's no duplication problem to work around. It's
-- left-aligned (not centered, unlike title_page.lua's Title/Subtitle) --
-- a real memo reads top-left, not centered like a formal report cover --
-- and the logo (if set) defaults to left alignment for the same reason
-- (title_page.lua's logo defaults to centered).
--
-- Deliberately does NOT emit `quartifyr-front-matter-start` (unlike
-- title_page.lua) -- see utils.front_matter_start_bookmark()'s comment
-- for why: a memo has no other front-matter content between its cover
-- and `{{< body-start >}}`, so giving the cover its own OOXML section
-- here would render as a genuinely blank page between the cover and the
-- body (confirmed in practice). The cover's manual page break plus
-- `{{< body-start >}}`'s own section boundary is enough on its own.
--
-- Mutual exclusivity with `title:`: this filter skips entirely (with a
-- warning) if `title:` is also set, mirroring title_page.lua's own
-- "missing title, skipping" guard in reverse -- not because of any
-- bookmark collision (this filter doesn't emit one), but because
-- rendering both a title page and a memo banner in the same document
-- would just produce two conflicting, stacked cover pages.

local utils = require("quartifyr_utils")

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

-- Fixed display order -- a YAML list isn't needed here (unlike
-- title-page-extra/synopsis) since these five fields are always the
-- same fixed set, not open-ended.
local MEMO_FIELD_ORDER = {
  { key = "to", label = "To" },
  { key = "from", label = "From" },
  { key = "date", label = "Date" },
  { key = "re", label = "Re" },
  { key = "cc", label = "Cc" },
}

local has_memo = false
local has_title = false
local memo_heading = "MEMORANDUM"
local document_status = "DRAFT"
local field_rows = {} -- list of {label=, value=}, in MEMO_FIELD_ORDER order
local logo_path = nil
local logo_width = "2in"
local logo_align = "left"

-- A real, visible Heading1 -- see file-header comment for why this
-- doesn't need title_page.lua's invisible-tiny-heading trick. Left
-- aligned via Heading1's own (left) style default -- no explicit `jc`
-- override, unlike title_page.lua's centered Title/Subtitle.
local function banner_paragraph(text)
  return string.format(
    [[
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Heading1"/>
    </w:pPr>
    <w:r><w:t xml:space="preserve">%s</w:t></w:r>
  </w:p>
  ]],
    utils.escape_xml(text)
  )
end

return {
  {
    Meta = function(meta)
      has_title = stringify_or_nil(meta.title) ~= nil
      has_memo = meta.memo ~= nil

      if not has_memo then
        return meta
      end

      memo_heading = stringify_or_nil(meta["memo-heading"]) or "MEMORANDUM"
      document_status = stringify_or_nil(meta["document-status"]) or "DRAFT"
      logo_path = stringify_or_nil(meta.logo)
      logo_width = stringify_or_nil(meta["logo-width"]) or "2in"
      logo_align = stringify_or_nil(meta["logo-align"]) or "left"
      if logo_align ~= "left" and logo_align ~= "center" and logo_align ~= "right" then
        quarto.log.warning(
          "memo_cover.lua: logo-align must be 'left', 'center', or 'right' (got '"
            .. logo_align
            .. "'); defaulting to 'left'"
        )
        logo_align = "left"
      end

      for _, f in ipairs(MEMO_FIELD_ORDER) do
        local value = stringify_or_nil(meta.memo[f.key])
        if value then
          table.insert(field_rows, { label = f.label, value = value })
        end
      end

      return meta
    end,
  },
  {
    Pandoc = function(doc)
      if not has_memo then
        return doc
      end

      if has_title then
        quarto.log.warning(
          "memo_cover.lua: both 'title' and 'memo' are set in frontmatter; "
            .. "skipping the memo cover to avoid emitting a second, "
            .. "identically-named front-matter-start bookmark "
            .. "(title_page.lua already renders a cover page from 'title'). "
            .. "Remove 'title' from frontmatter to render the memo cover "
            .. "instead."
        )
        return doc
      end

      -- Mixed list of pandoc blocks (RawBlock strings get accumulated and
      -- flushed as a group; the logo, when present, is a genuine
      -- pandoc.Image block spliced in between -- see utils.logo_block()'s
      -- comment for why it can't just be more raw OOXML).
      local blocks = {}
      local ooxml_parts = {}

      local function flush_ooxml()
        if #ooxml_parts > 0 then
          table.insert(blocks, utils.raw_block(table.concat(ooxml_parts, "\n")))
          ooxml_parts = {}
        end
      end

      if logo_path then
        table.insert(blocks, utils.logo_block(logo_path, logo_width, logo_align))
      end

      table.insert(ooxml_parts, banner_paragraph(string.upper(memo_heading)))
      table.insert(ooxml_parts, utils.spacer_paragraph())

      if #field_rows > 0 then
        table.insert(ooxml_parts, utils.field_table(field_rows))
      end

      table.insert(ooxml_parts, utils.spacer_paragraph())
      table.insert(ooxml_parts, utils.status_box(document_status))

      -- No front_matter_start_bookmark() here -- see file-header comment
      -- and utils.front_matter_start_bookmark()'s own comment for why.
      table.insert(ooxml_parts, utils.page_break_paragraph())

      flush_ooxml()

      -- Insert the whole ordered `blocks` list at the front of the
      -- document, in one pass, by inserting each element at position 1
      -- starting from the *last* one -- each insert pushes the prior
      -- ones down, so working backwards yields the correct final order.
      for i = #blocks, 1, -1 do
        table.insert(doc.blocks, 1, blocks[i])
      end

      return doc
    end,
  },
}
