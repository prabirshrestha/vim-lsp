" This is copied from https://github.com/natebosch/vim-lsc/blob/master/autoload/lsc/diff.vim
"
" Computes a simplistic diff between [old] and [new].
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
"
" Finds a single change between the common prefix, and common postfix.
let s:has_lua = has('nvim-0.4.0') || (has('lua') && has('patch-8.2.0775'))

function! s:init_lua() abort
  lua <<EOF
  -- Returns a zero-based index of the last line that is different between
  -- old and new. If old and new are not zero indexed, pass offset to indicate
  -- the index base.
  function vimlsp_last_difference(old, new, offset, line_count)
    for i = 0, line_count - 1 do
      if old[#old - i + offset] ~= new[#new - i + offset] then
        return -1 * i
      end
    end
    return -1 * line_count
  end
  -- Returns a zero-based index of the first line that is different between
  -- old and new. If old and new are not zero indexed, pass offset to indicate
  -- the index base.
  function vimlsp_first_difference(old, new, offset, line_count)
    for i = 0, line_count - 1 do
      if old[i + offset] ~= new[i + offset] then
        return i
      end
    end
    return line_count - 1
  end
EOF
	let s:lua = 1
endfunction

if s:has_lua && !exists('s:lua')
  call s:init_lua()
endif

function! lsp#utils#diff#compute(old, new) abort
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
  if g:lsp_use_lua && s:has_lua
    let l:eval = has('nvim') ? 'vim.api.nvim_eval' : 'vim.eval'
    let l:i = luaeval('vimlsp_first_difference('
        \.l:eval.'("a:old"),'.l:eval.'("a:new"),'.l:eval.'("has(\"nvim\")"),'.l:line_count.')')
  else
	for l:i in range(l:line_count)
	  if a:old[l:i] !=# a:new[l:i] | break | endif
	endfor
  endif
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
  if g:lsp_use_lua && s:has_lua
    let l:eval = has('nvim') ? 'vim.api.nvim_eval' : 'vim.eval'
    let l:i = luaeval('vimlsp_last_difference('
        \.l:eval.'("a:old"),'.l:eval.'("a:new"),'.l:eval.'("has(\"nvim\")"),'.l:line_count.')')
  else
	for l:i in range(-1, -1 * l:line_count, -1)
	  if a:old[l:i] !=# a:new[l:i] | break | endif
	endfor
  endif
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
