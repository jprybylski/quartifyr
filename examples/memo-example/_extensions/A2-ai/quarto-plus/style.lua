local utils = require("utils")

-- Shortcode that allows for in-line use of custom styles (as opposed to using custom-styles via divs)
return {
  ['style'] = function(args, kwargs, meta)
    local style = args[1] or "Normal"
    local text = args[2] or "If you see this, you did not provide text to be used with the custom style."

    quarto.log.debug("Using custom style shortcode")
    quarto.log.debug("Style: " .. style)
    quarto.log.debug("Text: " .. text)

    local openxml = string.format([[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="%s"/>
      </w:pPr>
      <w:r>
        <w:t>%s</w:t>
      </w:r>
    </w:p>
    ]], utils.escape_xml(style), utils.escape_xml(text))
    return pandoc.RawBlock('openxml', openxml)
  end
}
