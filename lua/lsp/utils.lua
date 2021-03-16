local M = {}

local DictM = {}
function DictM.__call(tbl)
  -- TODO: deal with `lua-special-tbl` in nvim
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
    if v[vim.type_idx] ~= nil then
      return v[vim.type_idx] == vim.types.dictionary
    else
      return true
    end
  else
    return false
  end
end

function M.binary_search(a, value, comparator)
  local lo = 1
  local hi = #a
  while lo <= hi do
    local mid = lo + math.floor((hi - lo) / 2)
    local cmp = comparator(value, a[mid])
    if cmp < 0 then
      hi = mid - 1
    elseif cmp > 0 then
      lo = mid + 1
    else
      return mid
    end
  end
  return -1
end

function M.filter(lst, cond)
  local new_lst = {}
  for item in M.list_wrapper(lst)() do
    if cond(item) then
      table.insert(new_lst, item)
    end
  end
  return new_lst
end

function M.binary_filter(a, value, comparator)
  local lo = 1
  local hi = #a
  while lo <= hi do
    local mid = lo + math.floor((hi - lo) / 2)
    local cmp = comparator(value, a[mid])
    if cmp < 0 then
      hi = mid - 1
    elseif cmp > 0 then
      lo = mid + 1
    else
      local result = {a[mid]}
      local left = mid - 1
      local right = mid + 1
      while right <= #a do
        local cmp = comparator(value, a[right])
        if cmp > 0 then
          break
        elseif cmp == 0 then
          result[#result + 1] = a[right]
        end
        right = right + 1
      end
      while left >= 1 do
        local cmp = comparator(value, a[left])
        if cmp < 0 then
          break
        elseif cmp == 0 then
          table.insert(result, 1, a[left])
        end
        left = left - 1
      end
      return result
    end
  end
  return {}
end

return M
