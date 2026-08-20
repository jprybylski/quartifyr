-- Shortcodes for numbered appendices, and for figure/table numbering
-- scoped to an appendix, a top-level section, or a subsection instead of
-- running continuously through the whole document:
--
--   {{< appendix "StatsAppendix" "Statistical Analysis Details" >}}
--   {{< appendix_crossref "StatsAppendix" >}}
--   {{< appendix_fig_caption "FigResiduals" "Residual plot" >}}
--   {{< appendix_tbl_caption "TblCoefficients" "Model coefficients" >}}
--   {{< section_break >}}
--   {{< section_fig_caption "FigDoseResponse" "Dose-response curve" >}}
--   {{< subsection_break >}}
--   {{< subsection_fig_caption "FigSubgroup" "Subgroup analysis" >}}
--   {{< scoped_crossref "FigResiduals" >}}
--
-- `appendix` auto-letters each appendix heading ("Appendix A", "Appendix
-- B", ...) via a native Word SEQ field, so adding/removing/reordering
-- appendices never requires manual renumbering -- just recalculate fields
-- (Quarto's docx output flags fields dirty; see the repo-root README for
-- the field-recalculation step). Its designator style defaults to
-- letters but is configurable document-wide via `appendix-numbering:`
-- frontmatter (`"alphabetic"` (default) / `"arabic"` / `"roman"`,
-- uppercase roman only -- the conventional choice for appendix
-- designators, matching Word's `\* ROMAN` switch as opposed to its
-- separate lowercase `\* roman` one).
--
-- The field's cached result (the text between its `separate` and `end`
-- fldChar, shown until the next recalculation) is pre-computed here to
-- match this appendix's actual position, not hardcoded to "A" -- confirmed
-- via a real Word test that a hardcoded "A" breaks the *ToC* (though never
-- the heading itself) for every appendix past the first: Word's ToC field
-- is positioned earlier in the document than the appendices, so a single
-- whole-document field-update pass builds ToC entries from each heading's
-- *current* text before that heading's own SEQ field has been recalculated
-- further down -- the heading ends up correct (Word recalculates it later
-- in the same pass), but the ToC entry keeps whatever was cached on disk.
-- Baking the correct letter in up front means both agree even before any
-- recalculation happens at all, sidestepping the ordering issue rather
-- than depending on Word to resolve it. The live SEQ field is untouched,
-- so reordering/adding/removing appendices by hand in Word afterward still
-- auto-reletters on the next recalculation as designed.
--
-- It uses the "Heading 1" style (referenced
-- by its style ID, "Heading1" with no space -- NOT its display name
-- "Heading 1" with a space; using the display name renders visually fine
-- but Word's ToC field silently fails to recognize the paragraph as a
-- heading at all, confirmed via a real Word field-recalculation test) so
-- appendices show up in quarto-plus's native ToC (`\o "1-3"`) the same way
-- any other top-level heading does, no `toc-style-map` needed.
--
-- `appendix_crossref` inserts an "Appendix X" hyperlink-style reference
-- back to a bookmark set by `appendix`, mirroring quarto-plus's own
-- tbl_caption/fig_caption/crossref shortcodes -- reimplemented here rather
-- than reused since theirs are hardcoded to the "Table"/"Figure" SEQ names.
--
-- SCOPED FIGURE/TABLE NUMBERING: quarto-plus's own `fig_caption`/
-- `tbl_caption` (its `crossref.lua`, vendored per-project under
-- `_extensions/A2-ai/quarto-plus/`, not part of quartifyr) number
-- continuously through the whole document -- "Figure 12" inside Appendix
-- B, not "Figure B.1". `appendix_fig_caption`/`appendix_tbl_caption`,
-- `section_fig_caption`/`section_tbl_caption`, and
-- `subsection_fig_caption`/`subsection_tbl_caption` are additive
-- alternatives an author can use in place of quarto-plus's own shortcode
-- wherever scoped numbering is wanted. Every level joins onto the next
-- with a period, matching how Word's own "include chapter number in
-- caption" feature numbers a document's real chapters/sections (e.g.
-- "Figure 2-1"/"Figure 2.1") and ISO 2145's convention for numbering
-- subdivisions of a document (a full stop between each level) -- not
-- run together undelimited the way APA style's own appendix-figure
-- convention does ("Figure A1"), which reads ambiguously here once
-- `appendix-numbering: arabic` is in play ("Figure 11" -- the first
-- figure of appendix 1, or the eleventh figure?):
--
--   {{< appendix_fig_caption "FigResiduals" "Residual plot" >}}
--
-- numbers "Figure A.1" -- that appendix's own designator (from
-- `appendix-numbering:` above), a period, then a number that restarts at
-- 1 for each new `{{< appendix >}}`.
--
--   {{< section_break >}}
--   {{< section_fig_caption "FigDoseResponse" "Dose-response curve" >}}
--
-- numbers "Figure 3.1" in the main body (the "3" from the most recent
-- `{{< section_break >}}`) -- but "Figure C.3.1" if that same
-- `section_break`/`section_fig_caption` pair instead appears *after* an
-- `{{< appendix >}}` call, prefixed with that appendix's own designator:
-- a figure numbered "Figure 3.1" deep inside an appendix would otherwise
-- read as though it belongs to the third *main-body* section, when nothing
-- about its number says "this is inside an appendix" at all. Every
-- `{{< appendix >}}` call resets the section/subsection counters back to
-- 0 for exactly this reason -- so the first `section_break` after a new
-- appendix always starts that appendix's own nested numbering at ".1",
-- not wherever the main body's own section count happened to leave off.
-- `{{< subsection_break >}}`/`subsection_fig_caption` do the same one
-- level deeper: "Figure 3.2.1" in the main body, "Figure C.3.2.1" inside
-- an appendix.
--
-- Nothing here forks or modifies quarto-plus's own crossref.lua -- these
-- are new shortcode names, not a replacement, and an author can freely
-- mix scoped and continuous captions in the same document.
--
-- Why section/subsection scope needs an explicit `{{< section_break >}}`/
-- `{{< subsection_break >}}` marker rather than just resetting
-- automatically at each native `#`/`##` heading: see the repo-root
-- CLAUDE.md's "Architecture notes that span files" section. Not validated
-- or enforced -- placement is the author's responsibility, same as
-- `appendix_crossref`'s bookmark target today.
--
-- LIST OF FIGURES/TABLES: none of the scoped captions show up in
-- quarto-plus's own `.list_of_figures`/`.list_of_tables` div (its
-- `table_of_contents.lua`) -- that's built from Word's native
-- `TOC \c "Figure"`/`TOC \c "Table"` field switch, which only collects
-- entries from the literal `SEQ Figure`/`SEQ Table` sequences
-- quarto-plus's own fig_caption/tbl_caption use, not the separate
-- `SEQ AppendixFigure`/`SEQ SectionFigure`/etc. sequences here -- and
-- can't, short of running two competing counters under one shared field
-- name. `caption_lists.lua`'s own `.quartifyr_list_of_figures`/
-- `.quartifyr_list_of_tables` divs are the fix: a combined, hand-built
-- list (not a native TOC field) spanning both these six scoped shortcodes
-- and quarto-plus's own continuous ones, in true document order. See that
-- file's header comment for how.

local utils = require("quartifyr_utils")

-- Offset away from quarto-plus's own crossref.lua bookmark ids (which
-- start at 1 and increment per caption) so the two extensions' w:id
-- values can never collide within the same document -- also clear of
-- layout.py's SAME_PAGE_MARKER_ID_BASE (950000+, see
-- quartifyr_styling/_ooxml_fields.py), with 50000 ids of headroom, ample
-- for any realistic document even with every caption in it scoped.
local next_id = 900000

local function alloc_id()
  next_id = next_id + 1
  return next_id
end

-- Appendix position + designator style, e.g. Word's own SEQ \* ALPHABETIC
-- output: 1=A, ..., 26=Z, 27=AA, 28=AB, ... (bijective base-26, same
-- scheme as spreadsheet column letters -- see quartifyr_utils.lua).
local appendix_count = 0
local current_appendix_designator = nil -- nil until the first {{< appendix >}}

local APPENDIX_NUMBERING_STYLES = {
  alphabetic = { seq_switch = "ALPHABETIC", generator = utils.to_alphabetic },
  arabic = { seq_switch = "ARABIC", generator = function(n) return tostring(n) end },
  roman = { seq_switch = "ROMAN", generator = utils.to_roman },
}

-- Section/subsection ordinals, advanced only by section_break/
-- subsection_break -- see the file header comment on why these can't be
-- derived automatically from native #/## headings.
local current_section_number = 0
local current_subsection_number = 0

-- Per-scope figure/table counters. `<scope>_needs_reset` is consumed
-- (and cleared) by the next caption in that scope: only that one caption
-- gets an explicit `\r 1` SEQ reset switch baked in, so Word's own live
-- recalculation restarts at 1 there too instead of continuing whatever
-- that named SEQ sequence last held.
local scopes = {
  appendix = { fig = 0, tbl = 0, fig_needs_reset = true, tbl_needs_reset = true },
  section = { fig = 0, tbl = 0, fig_needs_reset = true, tbl_needs_reset = true },
  subsection = { fig = 0, tbl = 0, fig_needs_reset = true, tbl_needs_reset = true },
}

-- bookmark_id -> {label = "Figure"/"Table", text = "<baked composite number>"},
-- populated by every scoped caption shortcode, read by scoped_crossref.
local scoped_bookmarks = {}

-- Fires once per document, the first time section_fig_caption/
-- subsection_fig_caption produces a *plain* (not appendix-nested)
-- composite number ("Figure 3.1"), since that's the one case where a
-- reader could plausibly mistake it for being related to quarto-plus's
-- own continuous fig_caption/tbl_caption ("Figure 1", "Figure 2", ...) --
-- appendix-nested numbers ("Figure C.3.1") don't have this problem, the
-- leading letter already marks them as a different sequence. Lua can't
-- see whether continuous captions are *actually* used anywhere in this
-- document (they're `quarto-plus`'s own shortcode, a separate extension
-- with no shared state), so this can't detect real mixing -- it's a
-- standing reminder every time plain scoped numbering is used at all.
local warned_plain_scope_independence = false

local function note_plain_scope_independence()
  if warned_plain_scope_independence then
    return
  end
  warned_plain_scope_independence = true
  quarto.log.warning(
    "section_fig_caption/section_tbl_caption/subsection_fig_caption/"
      .. "subsection_tbl_caption number independently of quarto-plus's own "
      .. "continuous fig_caption/tbl_caption (\"Figure 1\", \"Figure 2\", ...) "
      .. "-- a \"Figure N.M\" caption here has no relationship to any "
      .. "continuous \"Figure N\" caption elsewhere in the document, even one "
      .. "with a matching number; each is its own separate counter. If both "
      .. "appear in the same document, consider using one convention "
      .. "consistently per figure/table type so a reader doesn't assume a "
      .. "connection that isn't there."
  )
end

-- Every level of a composite number joins onto the next with a period --
-- see the file header comment for why (ISO 2145 / Word's own
-- chapter-numbered-caption convention, and disambiguation against
-- `appendix-numbering: arabic`). Builds the dot-joined prefix that
-- precedes a scoped caption's own local number: just the appendix
-- designator for `appendix` scope; the section (and subsection) ordinal
-- for `section`/`subsection` scope, itself prefixed with the current
-- appendix's designator too whenever one is active (`{{< appendix >}}`
-- resets the section/subsection counters on every call specifically so
-- this nesting always starts fresh per appendix -- see `appendix`'s own
-- handler below).
local function scope_prefix(scope_key)
  local appendix_active = current_appendix_designator ~= nil

  if scope_key == "appendix" then
    if not appendix_active then
      quarto.log.warning(
        "appendix_fig_caption/appendix_tbl_caption used before any {{< appendix >}} -- numbering will show '?'"
      )
      return "?"
    end
    return current_appendix_designator
  elseif scope_key == "section" then
    if current_section_number == 0 then
      quarto.log.warning(
        "section_fig_caption/section_tbl_caption used before any {{< section_break >}} -- numbering will show '?'"
      )
      return "?"
    end
    if not appendix_active then
      note_plain_scope_independence()
    end
    local parts = {}
    if appendix_active then
      table.insert(parts, current_appendix_designator)
    end
    table.insert(parts, tostring(current_section_number))
    return table.concat(parts, ".")
  else -- subsection
    if current_section_number == 0 or current_subsection_number == 0 then
      quarto.log.warning(
        "subsection_fig_caption/subsection_tbl_caption used before any {{< subsection_break >}} -- numbering will show '?'"
      )
      return "?"
    end
    if not appendix_active then
      note_plain_scope_independence()
    end
    local parts = {}
    if appendix_active then
      table.insert(parts, current_appendix_designator)
    end
    table.insert(parts, tostring(current_section_number))
    table.insert(parts, tostring(current_subsection_number))
    return table.concat(parts, ".")
  end
end

-- Builds the appendix_fig_caption/appendix_tbl_caption/section_.../
-- subsection_... shortcode handlers -- all six share this one
-- implementation, parameterized by which scope's counters/prefix to use,
-- the display label ("Figure"/"Table"), and the Word SEQ field name that
-- scope+label's counter lives under (each of the six needs its own,
-- distinct from quarto-plus's own "Figure"/"Table" SEQ names -- see the
-- file header's List of Figures/Tables limitation).
local function make_scoped_caption(scope_key, counter_key, label, seq_name)
  return function(args, _kwargs, meta)
    local bookmark_id = (args[1] or "defaultBookId"):gsub("%s+", "")
    local caption_text = args[2] or "If you see this, you did not provide caption text."
    local style = pandoc.utils.stringify(
      meta and (label == "Table" and meta["caption-style-table"] or meta["caption-style-figure"]) or "Caption"
    )
    local id = alloc_id()

    local scope = scopes[scope_key]
    scope[counter_key] = scope[counter_key] + 1
    local local_number = scope[counter_key]

    local prefix = scope_prefix(scope_key)
    local composite_number = prefix .. "." .. tostring(local_number)

    local reset_flag_key = counter_key .. "_needs_reset"
    local reset_switch = ""
    if scope[reset_flag_key] then
      reset_switch = " \\r 1"
      scope[reset_flag_key] = false
    end

    scoped_bookmarks[bookmark_id] = { label = label, text = composite_number }

    local ooxml = string.format(
      [[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="%s"/>
      </w:pPr>
      <w:bookmarkStart w:id="%d" w:name="%s"/>
      <w:r>
        <w:t xml:space="preserve">%s </w:t>
      </w:r>
      <w:r>
        <w:t xml:space="preserve">%s</w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="begin" w:dirty="true"/>
      </w:r>
      <w:r>
        <w:instrText xml:space="preserve"> SEQ %s \* ARABIC%s </w:instrText>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="separate"/>
      </w:r>
      <w:r>
        <w:t>%d</w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="end"/>
      </w:r>
      <w:bookmarkEnd w:id="%d"/>
      <w:r>
        <w:tab/>
          <w:t>%s</w:t>
      </w:r>
    </w:p>
    ]],
      utils.escape_xml(style),
      id,
      utils.escape_xml(bookmark_id),
      label,
      utils.escape_xml(prefix .. "."),
      seq_name,
      reset_switch,
      local_number,
      id,
      utils.escape_xml(caption_text)
    )

    return pandoc.RawBlock("openxml", ooxml)
  end
end

local function reset_scope_counters(scope_key)
  scopes[scope_key].fig = 0
  scopes[scope_key].tbl = 0
  scopes[scope_key].fig_needs_reset = true
  scopes[scope_key].tbl_needs_reset = true
end

-- Zero-output boundary markers: no bookmark, no downstream consumer needs
-- to locate these positionally (unlike body_start.lua's bookmark, which
-- apply-layout.py has to find later) -- just advance Lua-side counters,
-- so an empty block list renders as truly nothing rather than an extra
-- blank paragraph.
local function section_break(_args, _kwargs, _meta)
  current_section_number = current_section_number + 1
  current_subsection_number = 0
  reset_scope_counters("section")
  reset_scope_counters("subsection")
  return pandoc.Blocks({})
end

local function subsection_break(_args, _kwargs, _meta)
  current_subsection_number = current_subsection_number + 1
  reset_scope_counters("subsection")
  return pandoc.Blocks({})
end

return {
  ["appendix"] = function(args, _kwargs, meta)
    local bookmark_id = (args[1] or "defaultAppendixId"):gsub("%s+", "")
    local title = args[2] or "If you see this, you did not provide an appendix title."
    local id = alloc_id()

    local numbering_style_name = pandoc.utils.stringify(meta and meta["appendix-numbering"] or "alphabetic")
    if numbering_style_name == "" then
      numbering_style_name = "alphabetic"
    end
    local numbering_style = APPENDIX_NUMBERING_STYLES[numbering_style_name]
    if not numbering_style then
      quarto.log.warning(
        "appendix-numbering: unrecognized value '" .. numbering_style_name .. "', falling back to 'alphabetic'"
      )
      numbering_style = APPENDIX_NUMBERING_STYLES.alphabetic
    end

    appendix_count = appendix_count + 1
    local designator = numbering_style.generator(appendix_count)
    current_appendix_designator = designator

    -- New appendix: figure/table numbering inside it starts fresh, and so
    -- does any section/subsection scoping from here on -- a
    -- {{< section_break >}} after this point nests under *this*
    -- appendix's own designator (see scope_prefix()), starting at ".1"
    -- again rather than continuing whatever the main body's (or an
    -- earlier appendix's) own section count happened to reach.
    reset_scope_counters("appendix")
    current_section_number = 0
    current_subsection_number = 0
    reset_scope_counters("section")
    reset_scope_counters("subsection")

    local ooxml = string.format(
      [[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="Heading1"/>
      </w:pPr>
      <w:bookmarkStart w:id="%d" w:name="%s"/>
      <w:r>
        <w:t xml:space="preserve">Appendix </w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="begin" w:dirty="true"/>
      </w:r>
      <w:r>
        <w:instrText xml:space="preserve"> SEQ Appendix \* %s </w:instrText>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="separate"/>
      </w:r>
      <w:r>
        <w:t>%s</w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="end"/>
      </w:r>
      <w:bookmarkEnd w:id="%d"/>
      <w:r>
        <w:t xml:space="preserve">: %s</w:t>
      </w:r>
    </w:p>
    ]],
      id,
      utils.escape_xml(bookmark_id),
      numbering_style.seq_switch,
      designator,
      id,
      utils.escape_xml(title)
    )

    return pandoc.RawBlock("openxml", ooxml)
  end,

  ["appendix_crossref"] = function(args, _kwargs, _meta)
    local bookmark_id = (args[1] or "defaultAppendixId"):gsub("%s+", "")

    local ooxml = string.format(
      [[
    <w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:fldChar w:fldCharType="begin" w:dirty="true"/>
    </w:r>
    <w:r>
      <w:instrText xml:space="preserve"> REF %s \h </w:instrText>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="separate"/>
    </w:r>
    <w:r>
      <w:t>Appendix ?</w:t>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="end"/>
    </w:r>
    ]],
      utils.escape_xml(bookmark_id)
    )

    return pandoc.RawInline("openxml", ooxml)
  end,

  ["appendix_fig_caption"] = make_scoped_caption("appendix", "fig", "Figure", "AppendixFigure"),
  ["appendix_tbl_caption"] = make_scoped_caption("appendix", "tbl", "Table", "AppendixTable"),
  ["section_fig_caption"] = make_scoped_caption("section", "fig", "Figure", "SectionFigure"),
  ["section_tbl_caption"] = make_scoped_caption("section", "tbl", "Table", "SectionTable"),
  ["subsection_fig_caption"] = make_scoped_caption("subsection", "fig", "Figure", "SubsectionFigure"),
  ["subsection_tbl_caption"] = make_scoped_caption("subsection", "tbl", "Table", "SubsectionTable"),

  ["section_break"] = section_break,
  ["subsection_break"] = subsection_break,

  ["scoped_crossref"] = function(args, _kwargs, _meta)
    local bookmark_id = (args[1] or "defaultBookId"):gsub("%s+", "")
    local entry = scoped_bookmarks[bookmark_id]
    local label, text
    if entry then
      label, text = entry.label, entry.text
    else
      quarto.log.warning("scoped_crossref: no scoped caption found for bookmark ID: " .. bookmark_id)
      label, text = "Unknown", "??"
    end

    local ooxml = string.format(
      [[
    <w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:fldChar w:fldCharType="begin" w:dirty="true"/>
    </w:r>
    <w:r>
      <w:instrText xml:space="preserve"> REF %s \h </w:instrText>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="separate"/>
    </w:r>
    <w:r>
      <w:t>%s %s</w:t>
    </w:r>
    <w:r>
      <w:fldChar w:fldCharType="end"/>
    </w:r>
    ]],
      utils.escape_xml(bookmark_id),
      utils.escape_xml(label),
      utils.escape_xml(text)
    )

    return pandoc.RawInline("openxml", ooxml)
  end,
}
