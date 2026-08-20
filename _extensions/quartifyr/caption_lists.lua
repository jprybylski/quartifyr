-- Marks the position of a combined List of Figures/List of Tables --
-- spanning BOTH quarto-plus's own continuous fig_caption/tbl_caption AND
-- quartifyr's six scoped caption shortcodes (appendix_fig_caption/
-- appendix_tbl_caption, section_fig_caption/section_tbl_caption,
-- subsection_fig_caption/subsection_tbl_caption -- appendix.lua), in true
-- document order regardless of how a project mixes them:
--
--   ::: .quartifyr_list_of_figures
--   :::
--
--   ::: .quartifyr_list_of_tables
--   :::
--
-- Distinct from quarto-plus's own `.list_of_figures`/`.list_of_tables`
-- divs (its table_of_contents.lua) -- those stay exactly as they are,
-- continuous-only, for a project that never uses a scoped caption; this
-- is additive, not a replacement.
--
-- WHY THIS EXISTS: `.list_of_figures`/`.list_of_tables` are built from a
-- native Word `TOC \c "Figure"`/`TOC \c "Table"` field switch, which only
-- collects entries carrying the literal `SEQ Figure`/`SEQ Table`
-- sequences fig_caption/tbl_caption use -- not the six separate SEQ names
-- the scoped captions use (SEQ AppendixFigure, SEQ SectionFigure, ...),
-- since those need independent counters that restart per scope. `TOC \c`
-- is also capped at one SEQ identifier with no merge/sort option, so
-- concatenating one `TOC \c` field per SEQ family doesn't work either --
-- each field independently scans the *whole* document for its own SEQ
-- name, so the result is grouped by numbering family (all continuous
-- entries, then all appendix-scoped entries, then all section-scoped
-- entries, ...), not interleaved by actual document position -- backwards
-- from what "List of Figures" means in any style guide. See
-- appendix.lua's file-header comment for the full story.
--
-- WHY THIS FILTER ONLY EMITS A BOOKMARK, NOT THE FINISHED LIST: this
-- needs to see every caption in the whole document -- including
-- appendix-/section-/subsection-scoped ones that only exist as raw OOXML
-- *after* quarto-plus's and this extension's own shortcodes
-- (fig_caption/tbl_caption, appendix_fig_caption/appendix_tbl_caption/
-- ...) have expanded. Confirmed empirically (rendering a real document
-- and inspecting `doc.blocks` from inside this file's own `Pandoc`-stage
-- function): shortcode expansion happens in a pass that runs strictly
-- *after* every `contributes: filters:` Lua filter from every extension
-- has already finished -- a `Pandoc`-stage function here still sees each
-- `{{< fig_caption ... >}}`/`{{< appendix_fig_caption ... >}}` call
-- unexpanded, regardless of this file's position in _extension.yml's
-- `filters:` list. So no Lua filter can walk a fully caption-resolved
-- document the way this feature needs. What Lua *can* still see, right
-- here, is the `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables`
-- placeholder Div itself -- ordinary pandoc fenced-div syntax, not a
-- shortcode, so it's already a real `Div` AST node at filter time. This
-- file marks each one it finds with a small bookmark
-- (`quartifyr-list-of-figures`/`quartifyr-list-of-tables`), the same
-- "leave a findable marker for a later post-render step" trick
-- title_page.lua's own `quartifyr-front-matter-start` bookmark already
-- uses for apply-layout's section-splitting (see quartifyr_utils.lua's
-- front_matter_start_bookmark()). `quartifyr_styling.layout`'s
-- `apply_layout()` (Python, post-render -- see that module and
-- `_caption_lists.py`) does the actual work once Quarto's full render,
-- shortcodes included, has produced a real `document.xml` with every
-- caption's bookmark/SEQ field genuinely present -- the same
-- "package-parts editing needs the finished docx" reasoning layout.py's
-- own module docstring already gives for the header/footer section
-- split.
local utils = require("quartifyr_utils")

local MARKER_IDS = {
  [".quartifyr_list_of_figures"] = { id = 800003, name = "quartifyr-list-of-figures" },
  [".quartifyr_list_of_tables"] = { id = 800004, name = "quartifyr-list-of-tables" },
}

local function marker_bookmark(id, name)
  return string.format(
    [[
  <w:p>
    <w:bookmarkStart w:id="%d" w:name="%s"/>
    <w:bookmarkEnd w:id="%d"/>
  </w:p>
  ]],
    id,
    utils.escape_xml(name),
    id
  )
end

return {
  {
    Div = function(div)
      for class, marker in pairs(MARKER_IDS) do
        if div.classes:includes(class) then
          table.insert(div.content, pandoc.RawBlock("openxml", marker_bookmark(marker.id, marker.name)))
          return div
        end
      end
      return nil
    end,
  },
}
