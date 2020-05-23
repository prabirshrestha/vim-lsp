" This is copied from https://github.com/natebosch/vim-lsc/blob/master/autoload/lsc/diff.vim
"
" Computes a simplistic diff between [old] and [new].
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
"
" Finds a single change between the common prefix, and common postfix.
let s:lua_initialized = 0

function! s:init_lua() abort
    let s:lua_initialized = 1

    lua <<EOF
    if vimlsp == nil then vimlsp = {} end
    if vimlsp.utils == nil then vimlsp.utils = {} end
    if vimlsp.utils.diff == nil then vimlsp.utils.diff = {} end

    local M = vimlsp.utils.diff

    local function first_difference(old, new)
        local line_count = math.min(#old, #new)
        if line_count == 0 then
            return 0, 0
        end
        local i = 0
        while i < line_count do
            if old[i] ~= new[i] then
                break
            end
            i = i + 1
        end
        if i >= line_count then
            return line_count - 1, vim.fn.strchars(old[line_count - 1])
        end
        local old_line = old[i]
        local new_line = new[i]
        local length = math.min(vim.fn.strchars(old_line), vim.fn.strchars(new_line))
        local j = 0
        while j < length do
            if vim.fn.strgetchar(old_line, j) ~= vim.fn.strgetchar(new_line, j) then
                break
            end
            j = j + 1
        end
        return i, j
    end

    function M.compute(old, new)
        local start_line, start_char = first_difference(old, new)
    end
EOF
endfunction

function! lsp#utils#diff#compute(old, new) abort
    if g:lsp_use_lua
        if !s:lua_initialized
            call s:init_lua()
        endif
        if has('nvim')
            lua vimlsp.utils.diff.compute(vim.api.nvim_eval('a:old'), vim.api.nvim_eval('a:new'))
        else
            lua vimlsp.utils.diff.compute(vim.eval('a:old'), vim.eval('a:new'))
        endif
        return s:vim_compute(a:old, a:new) " once lua is ported remove this
    else
        return s:vim_compute(a:old, a:new)
    endif
endfunction

function! s:vim_compute(old, new) abort
  let [l:start_line, l:start_char] = s:FirstDifference(a:old, a:new)
  let [l:end_line, l:end_char] =
      \ s:LastDifference(a:old[l:start_line :], a:new[l:start_line :], l:start_char)

  let l:text = s:ExtractText(a:new, l:start_line, l:start_char, l:end_line, l:end_char)
  let l:length = s:Length(a:old, l:start_line, l:start_char, l:end_line, l:end_char)

  let l:adj_end_line = len(a:old) + l:end_line
  let l:adj_end_char = l:end_line == 0 ? 0 : strchars(a:old[l:end_line]) + l:end_char + 1

  let l:result = { 'range': {'start': {'line': l:start_line, 'character': l:start_char},
      \ 'end': {'line': l:adj_end_line, 'character': l:adj_end_char}},
      \ 'text': l:text,
      \ 'rangeLength': l:length,
      \}

  return l:result
endfunction

" Finds the line and character of the first different character between two
" list of Strings.
function! s:FirstDifference(old, new) abort
  let l:line_count = min([len(a:old), len(a:new)])
  if l:line_count == 0 | return [0, 0] | endif
  let l:i = 0
  while l:i < l:line_count
    if a:old[l:i] !=# a:new[l:i] | break | endif
    let l:i += 1
  endwhile
  if l:i >= l:line_count
    return [l:line_count - 1, strchars(a:old[l:line_count - 1])]
  endif
  let l:old_line = a:old[l:i]
  let l:new_line = a:new[l:i]
  let l:length = min([strchars(l:old_line), strchars(l:new_line)])
  let l:j = 0
  while l:j < l:length
    if strgetchar(l:old_line, l:j) != strgetchar(l:new_line, l:j) | break | endif
    let l:j += 1
  endwhile
  return [l:i, l:j]
endfunction

function! s:LastDifference(old, new, start_char) abort
  let l:line_count = min([len(a:old), len(a:new)])
  if l:line_count == 0 | return [0, 0] | endif
  let l:i = -1
  while l:i >= -1 * l:line_count
    if a:old[l:i] !=# a:new[l:i] | break | endif
    let l:i -= 1
  endwhile
  if l:i <= -1 * l:line_count
    let l:i = -1 * l:line_count
    let l:old_line = strcharpart(a:old[l:i], a:start_char)
    let l:new_line = strcharpart(a:new[l:i], a:start_char)
  else
    let l:old_line = a:old[l:i]
    let l:new_line = a:new[l:i]
  endif
  let l:old_line_length = strchars(l:old_line)
  let l:new_line_length = strchars(l:new_line)
  let l:length = min([l:old_line_length, l:new_line_length])
  let l:j = -1
  while l:j >= -1 * l:length
    if  strgetchar(l:old_line, l:old_line_length + l:j) !=
        \ strgetchar(l:new_line, l:new_line_length + l:j)
      break
    endif
    let l:j -= 1
  endwhile
  return [l:i, l:j]
endfunction

function! s:ExtractText(lines, start_line, start_char, end_line, end_char) abort
  if a:start_line == len(a:lines) + a:end_line
    if a:end_line == 0 | return '' | endif
    let l:line = a:lines[a:start_line]
    let l:length = strchars(l:line) + a:end_char - a:start_char + 1
    return strcharpart(l:line, a:start_char, l:length)
  endif
  let l:result = strcharpart(a:lines[a:start_line], a:start_char) . "\n"
  for l:line in a:lines[a:start_line + 1:a:end_line - 1]
    let l:result .= l:line . "\n"
  endfor
  if a:end_line != 0
    let l:line = a:lines[a:end_line]
    let l:length = strchars(l:line) + a:end_char + 1
    let l:result .= strcharpart(l:line, 0, l:length)
  endif
  return l:result
endfunction

function! s:Length(lines, start_line, start_char, end_line, end_char) abort
  let l:adj_end_line = len(a:lines) + a:end_line
  if l:adj_end_line >= len(a:lines)
    let l:adj_end_char = a:end_char - 1
  else
    let l:adj_end_char = strchars(a:lines[l:adj_end_line]) + a:end_char
  endif
  if a:start_line == l:adj_end_line
    return l:adj_end_char - a:start_char + 1
  endif
  let l:result = strchars(a:lines[a:start_line]) - a:start_char + 1
  let l:line = a:start_line + 1
  while l:line < l:adj_end_line
    let l:result += strchars(a:lines[l:line]) + 1
    let l:line += 1
  endwhile
  let l:result += l:adj_end_char + 1
  return l:result
endfunction
