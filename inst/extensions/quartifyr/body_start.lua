-- {{< body-start >}}
--
-- Marks where "front matter" ends and the main body begins -- e.g. right
-- before your first real `# Introduction` heading. Purely a positional
-- marker: it renders as an empty bookmarked paragraph and produces no
-- visible content on its own.
--
-- `styling/quartifyr_styling/layout.py`'s post-processing step (run after
-- the Quarto render, via `quartifyr-styling apply-layout`) looks for the
-- `quartifyr-body-start` bookmark this leaves behind and splits the
-- document into two OOXML sections there: front matter (title page,
-- signatures, synopsis, ToC, abbreviations, ...) and body. This is what
-- makes page numbering able to restart at 1 from your first body page
-- instead of counting front-matter pages -- see r/README.md's "Page
-- numbering and headers" section for why this needs a real Python
-- post-processing step rather than being achievable purely from a Lua
-- filter (creating a second, independent header/footer requires adding
-- new parts to the docx package, which Lua's RawBlock injection can't
-- do -- only python-docx's higher-level section API handles that
-- plumbing correctly).
--
-- Optional -- if you never use this shortcode, `apply-layout` finds no
-- bookmark and leaves the document as a single section (page numbering
-- counts every page from the start, as it does today without this
-- feature).

return {
  ["body-start"] = function(_args, _kwargs, _meta)
    local ooxml = [[
    <w:p>
      <w:bookmarkStart w:id="800001" w:name="quartifyr-body-start"/>
      <w:bookmarkEnd w:id="800001"/>
    </w:p>
    ]]
    return pandoc.RawBlock("openxml", ooxml)
  end,
}
