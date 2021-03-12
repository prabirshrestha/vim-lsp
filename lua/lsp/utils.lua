local M = {}

local DictM = {}
function DictM.__call(tbl)
  return pairs(tbl)
end

function M.dict_wrapper(dict)
  if type(dict) == 'table' then
    return setmetatable(dict, DictM)
  else
    return dict
  end
end

local ListM = {}
function ListM.__call(lst)
  local i = 0
  local cnt = #lst
  return function()
    i = i + 1
    if i <= cnt then
      return lst[i]
    end
  end
end

function M.list_wrapper(lst)
  if type(lst) == 'table' then
    return setmetatable(lst, ListM)
  else
    return lst
  end
end

function M.list()
  if vim.list then
    return vim.list()
  else
    return {[vim.type_idx]=vim.types.array}
  end
end

function M.is_dict(v)
  if vim.type then
    return vim.type(v) == 'dict'
  elseif type(v) == 'table' then
    return v[vim.type_idx] == vim.types.dictionary
  else
    return false
  end
end

return M
