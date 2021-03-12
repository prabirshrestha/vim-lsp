local M = {}
local utils = require('lsp/utils')

function M.foldexpr(folding_ranges, linenr)
  local foldlevel = 0
  local prefix = ''
  for folding_range in utils.list_wrapper(folding_ranges)() do
    if utils.is_dict(folding_range) and folding_range['startLine'] ~= nil and folding_range['endLine'] ~= nil then
      startline = folding_range['startLine'] + 1
      endline = folding_range['endLine'] + 1

      if startline <= linenr and linenr <= endline then
        foldlevel = foldlevel + 1
      end

      if startline == linenr then
        prefix = '>'
      elseif endline == linenr then
        prefix = '<'
      end
    end
  end
  return (prefix == '') and '=' or (prefix .. tostring(foldlevel))
end

return M
