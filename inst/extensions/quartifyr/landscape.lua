-- {{< landscape >}} / {{< portrait >}}
--
-- Marks where a landscape page section starts and where the document
-- returns to portrait, e.g. around a wide table or figure:
--
--   {{< landscape >}}
--   {{< appendix ... >}}  (or any heading, table or figure placeholder)
--   {{< portrait >}}
--
-- Purely positional markers, like `{{< body-start >}}`: each renders as an
-- empty bookmarked paragraph and produces no visible content on its own.
-- `quartifyr_styling/layout.py` (run after the Quarto render, via
-- `quartifyr-styling apply-layout`) finds the bookmarks and turns them
-- into real OOXML section breaks with swapped page dimensions, keeping the
-- header, footer and page numbering. Without that step they are inert.
--
-- Only the bookmark name matters to layout.py (`quartifyr-landscape-<n>`
-- / `quartifyr-portrait-<n>`); `<n>` just keeps names and ids unique when
-- a report switches orientation more than once.
--
-- The markers must come after `{{< body-start >}}`: everything before it
-- is front matter with its own roman page numbering, which layout.py
-- doesn't split further.
--
-- The break is a `w:sectPr` inside the marker paragraph's `w:pPr`, which
-- is ordinary paragraph markup, so it survives reportifyr's pass 2 the same
-- way the front-matter/body breaks already do.

local counter = 0

local function marker(kind)
  return function(_args, _kwargs, _meta)
    counter = counter + 1
    local ooxml = string.format([[
    <w:p>
      <w:bookmarkStart w:id="%d" w:name="quartifyr-%s-%d"/>
      <w:bookmarkEnd w:id="%d"/>
    </w:p>
    ]], 810000 + counter, kind, counter, 810000 + counter)
    return pandoc.RawBlock("openxml", ooxml)
  end
end

return {
  ["landscape"] = marker("landscape"),
  ["portrait"] = marker("portrait"),
}
