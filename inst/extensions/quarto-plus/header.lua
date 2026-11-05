local indent_headers = true

return {
  {
    Meta = function(meta)
      if meta["indent-headers"] ~= nil then
        indent_headers = pandoc.utils.stringify(meta["indent-headers"]) == "true"
      end
    end
  },
  {
    Header = function(el)
      quarto.log.debug("Processing header with level: " .. el.level)

      -- Check if the header is level 1 and has no content or an empty first text element
      if el.level == 1 and (#el.content == 0 or el.content[1].text == "") then
        quarto.log.debug("Header is level 1 and content is empty. Removing header")
        return {}
      end

      -- Check if the header has no content, and skip tab insertion if empty
      if #el.content == 0 then
        quarto.log.warning("Header has no content. Skipping tab insertion.")
        return el
      end

      if not indent_headers then
        quarto.log.debug("Header indentation disabled via indent-headers: false")
        return el
      end

      -- Insert a tab before the original heading text
      local original_content = pandoc.utils.stringify(el)
      quarto.log.debug("Original header content: " .. original_content)

      local tab = pandoc.Str("\t")
      table.insert(el.content, 1, tab)

      local modified_content = pandoc.utils.stringify(el)
      quarto.log.debug("Modified header content: " .. modified_content)

      return el
    end
  }
}
