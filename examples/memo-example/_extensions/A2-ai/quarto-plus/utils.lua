local M = {}

-- Escape XML special characters
function M.escape_xml(str)
  return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

return M
