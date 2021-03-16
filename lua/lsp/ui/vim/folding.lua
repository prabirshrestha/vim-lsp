local M = {}
local utils = require('lsp/utils')

local function valid_range(a)
  return utils.is_dict(a) and a['startLine'] ~= nil and a['endLine'] ~= nil
end

function M.sort(folding_ranges)
  table.sort(folding_ranges, function(a, b)
    if a['startLine'] ~= b['startLine'] then
      return a['startLine'] < b['startLine']
    end
    return a['endLine'] < b['endLine']
  end)
  return folding_ranges
end

local function in_range(linenr, range)
  return linenr < range['startLine'] and -1 or range['endLine'] < linenr and 1 or 0
end

function M.prepare(folding_ranges)
  return M.sort(utils.filter(folding_ranges, valid_range))
end

function M.foldexpr_sorted(folding_ranges, linenr)
  local linenr = linenr - 1
  local in_ranges = utils.binary_filter(folding_ranges, linenr, in_range)
  local foldlevel = #in_ranges
  if utils.binary_search(in_ranges, linenr, function (a, r) return a - r['startLine'] end) > 0 then
    return '>' .. tostring(foldlevel)
  elseif utils.binary_search(in_ranges, linenr, function (a, r) return a - r['endLine'] end) > 0 then
    return '<' .. tostring(foldlevel)
  else
    return '='
  end
end

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
