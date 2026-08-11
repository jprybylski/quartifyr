-- Initial tables and values to store mappings

local utils = require("utils")

local figure_id_map = {}    -- Table to store the figure bookmark_id
local table_id_map = {}     -- Table to store the table bookmark_id
local current_figure_id = 0 -- Initialize the sequence number for figures
local current_table_id = 0  -- Initialize the sequence number for tables
local current_bookmark_id = 0 -- Unique bookmark ID counter across all captions

-- Shortcode that allows for cross-referencing table captions
return {
  ['tbl_caption'] = function(args, kwargs, meta)
    local bookmark_id = (args[1] or "defaultBookId"):gsub("%s+", "")
    local caption_text = args[2] or "If you see this, you did not provide caption text."
    local style = pandoc.utils.stringify(meta["caption-style-table"] or "Caption")

    quarto.log.debug("Processing table caption with bookmark ID: " .. bookmark_id)
    quarto.log.debug("Caption text: " .. caption_text)

    -- Increment the sequence number for each new bookmark_id
    current_table_id = current_table_id + 1
    table_id_map[bookmark_id] = current_table_id
    current_bookmark_id = current_bookmark_id + 1

    quarto.log.debug("Updated tbl ID mapping: " .. bookmark_id .. " -> " .. current_table_id)

    local openxml = string.format([[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="%s"/>
      </w:pPr>
      <w:bookmarkStart w:id="%d" w:name="%s"/>
      <w:r>
        <w:t>Table</w:t>
      </w:r>
      <w:r>
        <w:t xml:space="preserve"> </w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="begin" w:dirty="true"/>
      </w:r>
      <w:r>
        <w:instrText xml:space="preserve"> SEQ Table \* ARABIC </w:instrText>
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
    ]], utils.escape_xml(style), current_bookmark_id, utils.escape_xml(bookmark_id), current_table_id, current_bookmark_id, utils.escape_xml(caption_text))
    return pandoc.RawBlock('openxml', openxml)
  end,

  -- Shortcode that allows for cross-referencing fig captions
  ['fig_caption'] = function(args, kwargs, meta)
    local bookmark_id = (args[1] or "defaultBookId"):gsub("%s+", "")
    local caption_text = args[2] or "If you see this, you did not provide caption text."
    local style = pandoc.utils.stringify(meta["caption-style-figure"] or "Caption")

    quarto.log.debug("Processing figure caption with bookmark ID: " .. bookmark_id)
    quarto.log.debug("Caption text: " .. caption_text)

    -- Increment the sequence number for each new bookmark_id
    current_figure_id = current_figure_id + 1
    figure_id_map[bookmark_id] = current_figure_id
    current_bookmark_id = current_bookmark_id + 1

    quarto.log.debug("Updated fig ID mapping: " .. bookmark_id .. " -> " .. current_figure_id)

    local openxml = string.format([[
    <w:p>
      <w:pPr>
        <w:pStyle w:val="%s"/>
      </w:pPr>
      <w:bookmarkStart w:id="%d" w:name="%s"/>
      <w:r>
        <w:t>Figure</w:t>
      </w:r>
      <w:r>
        <w:t xml:space="preserve"> </w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="begin" w:dirty="true"/>
      </w:r>
      <w:r>
        <w:instrText xml:space="preserve"> SEQ Figure \* ARABIC </w:instrText>
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
    ]], utils.escape_xml(style), current_bookmark_id, utils.escape_xml(bookmark_id), current_figure_id, current_bookmark_id, utils.escape_xml(caption_text))
    return pandoc.RawBlock('openxml', openxml)
  end,

  -- Shortcode that creates fig or tbl captions
  ['crossref'] = function(args, kwargs, meta)
    local bookmark_id = (args[1] or "defaultBookId"):gsub("%s+", "")
    quarto.log.debug("Processing cross-reference for bookmark ID: " .. bookmark_id)

    -- Determine if the bookmark_id is for a figure or a table by setting empty vars
    local x_value
    local label

    -- Logic to handle "Figure" or "Table" prefix, may not be needed
    if bookmark_id:match("^[Ff]igure") or bookmark_id:match("^[Ff]ig") then
      x_value = figure_id_map[bookmark_id]
      label = "Figure"
    elseif bookmark_id:match("^[Tt]able") or bookmark_id:match("^[Tt]bl") then
      x_value = table_id_map[bookmark_id]
      label = "Table"
    else
      x_value = "??"
      label = "Unknown"
      quarto.log.warning("Cross-reference bookmark ID does not match a figure or table pattern: " .. bookmark_id)
    end

    if not x_value then
      quarto.log.warning("No caption found for cross-reference: " .. bookmark_id .. ". Was the caption defined before this crossref?")
      x_value = "??"
    end

    local openxml = string.format([[
    <w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:fldChar w:fldCharType="begin"/>
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
    ]], utils.escape_xml(bookmark_id), utils.escape_xml(label), x_value)
    return pandoc.RawInline('openxml', openxml)
  end
}
