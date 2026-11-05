-- Defaults
local toc_levels = "1-3"
local toc_style_map = nil

-- Build the TOC instruction string from configuration
local function build_toc_instruction()
    local instr = string.format('TOC \\o "%s" \\h \\z', toc_levels)
    if toc_style_map then
        instr = instr .. string.format(' \\t "%s"', toc_style_map)
    else
        instr = instr .. ' \\u'
    end
    return instr
end

return {
    {
        Meta = function(meta)
            if meta["toc-levels"] then
                toc_levels = pandoc.utils.stringify(meta["toc-levels"])
            end
            if meta["toc-style-map"] then
                -- Build comma-separated style/level pairs from structured YAML list
                local pairs = {}
                for _, entry in ipairs(meta["toc-style-map"]) do
                    local style = pandoc.utils.stringify(entry.style)
                    local level = pandoc.utils.stringify(entry.level)
                    table.insert(pairs, style .. "," .. level)
                end
                toc_style_map = table.concat(pairs, ",")
            end
        end
    },
    {
        Div = function(el)
            quarto.log.debug("Processing Div element")

            -- Check for '.list_of_tables' class
            if el.classes:includes(".list_of_tables") then
                quarto.log.debug("Div element includes '.list_of_tables' class. Inserting List of Tables")

                -- OOXML content to insert a TOC for tables: \c "Table"
                local ooxml = [[
                <w:p>
                  <w:r>
                    <w:fldChar w:fldCharType="begin" w:dirty="true"/>
                  </w:r>
                  <w:r>
                    <w:instrText xml:space="preserve"> TOC \h \z \c "Table" </w:instrText>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="end"/>
                  </w:r>
                </w:p>
                ]]

                -- Insert the RawBlock into the div content
                table.insert(el.content, pandoc.RawBlock('openxml', ooxml))

                quarto.log.debug("List of Tables RawBlock inserted into Div element")

                return el

            -- Check for '.list_of_figures' class
            elseif el.classes:includes(".list_of_figures") then
                quarto.log.debug("Div element includes '.list_of_figures' class. Inserting List of Figures")

                -- OOXML content to insert a TOC for figures: \c "Figure"
                local ooxml = [[
                <w:p>
                  <w:r>
                    <w:fldChar w:fldCharType="begin" w:dirty="true"/>
                  </w:r>
                  <w:r>
                    <w:instrText xml:space="preserve"> TOC \h \z \c "Figure" </w:instrText>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="end"/>
                  </w:r>
                </w:p>
                ]]

                -- Insert the RawBlock into the div content
                table.insert(el.content, pandoc.RawBlock('openxml', ooxml))

                quarto.log.debug("List of Figures RawBlock inserted into Div element")

                return el

            -- Check for '.toc' class
            elseif el.classes:includes(".toc") then
                quarto.log.debug("Div element includes '.toc' class. Inserting Table of Contents")

                local toc_instr = build_toc_instruction()

                local ooxml = string.format([[
                <w:p>
                  <w:r>
                    <w:fldChar w:fldCharType="begin" w:dirty="true"/>
                  </w:r>
                  <w:r>
                    <w:instrText xml:space="preserve"> %s </w:instrText>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="separate"/>
                  </w:r>
                  <w:r>
                    <w:t>Right-click to update field</w:t>
                  </w:r>
                  <w:r>
                    <w:fldChar w:fldCharType="end"/>
                  </w:r>
                </w:p>
                ]], toc_instr)

                -- Insert the RawBlock into the div content
                table.insert(el.content, pandoc.RawBlock('openxml', ooxml))

                quarto.log.debug("Table of Contents RawBlock inserted into Div element")

                return el

            else
                quarto.log.debug("Div element does not match to classes: .list_of_tables, .list_of_figures, or .toc. No changes made")
            end
        end
    }
}
