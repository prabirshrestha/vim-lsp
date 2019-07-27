" This is copied from https://github.com/natebosch/vim-lsc/blob/master/autoload/lsc/diff.vim
"
" Computes a simplistic diff between [old] and [new].
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
"
" Finds a single change between the common prefix, and common postfix.
function! lsp#utils#diff#compute(old, new) abort
  let [l:start_line, l:start_char, l:start_offset] = lsp#utils#diff#first_difference(a:old, a:new)
  let [l:end_line, l:end_char, l:end_offset] = lsp#utils#diff#last_difference(a:old[l:start_line :], a:new[l:start_line :], l:start_char, l:start_offset)

  let l:text = lsp#utils#diff#extract_text(a:new, l:start_line, l:start_char, l:end_line, l:end_char)
  let l:length = lsp#utils#diff#length(a:old, l:start_line, l:start_char, l:end_line, l:end_char)

  let l:adj_end_line =  len(a:old) == 0 ? 0 : len(a:old) + l:end_line
  let l:adj_end_offset = len(a:old) == 0 ? 0 : l:end_offset

  let l:result = { 'range': {'start': {'line': l:start_line, 'character': l:start_offset},
      \ 'end': {'line': l:adj_end_line, 'character': l:adj_end_offset}},
      \ 'text': l:text,
      \ 'rangeLength': l:length,
      \}

  return l:result
endfunction

" Finds the line and character of the first different character between two
" list of Strings.
function! lsp#utils#diff#first_difference(old, new) abort
  let l:line_count = min([len(a:old), len(a:new)])
  if l:line_count == 0
    return [0, 0, 0]
  endif

  let l:first_diff_line = 0
  while l:first_diff_line < l:line_count
    if a:old[l:first_diff_line] !=# a:new[l:first_diff_line] | break | endif
    let l:first_diff_line += 1
  endwhile

  if l:first_diff_line >= l:line_count
    return [l:line_count - 1, strchars(a:old[l:line_count - 1]), lsp#utils#count_utf16_code_units(a:old[l:line_count - 1])]
  endif
  let l:old_line = a:old[l:first_diff_line]
  let l:new_line = a:new[l:first_diff_line]
  let l:length = min([strchars(l:old_line), strchars(l:new_line)])
  let l:j = 0
  let l:offset = 0
  while l:j < l:length
    if strgetchar(l:old_line, l:j) != strgetchar(l:new_line, l:j)
      break
    endif
    let l:offset += lsp#utils#count_utf16_code_units(nr2char(strgetchar(l:old_line, l:j)))
    let l:j += 1
  endwhile
  return [l:first_diff_line, l:j, l:offset]
endfunction

" Find last difference position
" It returns array
" 0 - -1 based line index, -1 is last line.
" 1 - -1 based char index, -1 is last character. it is not exclusive.
" 2 - 0 based utf16 code unit, 0 is first character. is is exclusive.
"
" @see https://github.com/Microsoft/language-server-protocol/blob/gh-pages/specification.md#range
function! lsp#utils#diff#last_difference(old, new, start_char, start_offset) abort
  if len(a:old) == 0
    return [-1, -1, 0]
  endif
  if len(a:new) == 0
    return [-1, -1, lsp#utils#count_utf16_code_units(a:old[-1])]
  endif

  let l:line_count = min([len(a:old), len(a:new)])
  let l:last_diff_line = -1
  while l:last_diff_line >= -1 * l:line_count
    if a:old[l:last_diff_line] !=# a:new[l:last_diff_line] | break | endif
    let l:last_diff_line -= 1
  endwhile

  let l:start_offset = a:start_offset
  if l:last_diff_line <= -1 * l:line_count
    let l:last_diff_line = -1 * l:line_count
    let l:old_line = strcharpart(a:old[l:last_diff_line], a:start_char)
    let l:new_line = strcharpart(a:new[l:last_diff_line], a:start_char)
  else
    let l:old_line = a:old[l:last_diff_line]
    let l:new_line = a:new[l:last_diff_line]
    let l:start_offset = 0
  endif

  let l:old_line_length = strchars(l:old_line)
  let l:new_line_length = strchars(l:new_line)
  let l:length = min([l:old_line_length, l:new_line_length])

  let l:j = -1
  let l:offset = 0
  while l:j >= -1 * l:length
    if strgetchar(l:old_line, l:old_line_length + l:j) != strgetchar(l:new_line, l:new_line_length + l:j)
      break
    endif
    let l:offset += lsp#utils#count_utf16_code_units(nr2char(strgetchar(l:old_line, l:old_line_length + l:j)))
    let l:j -= 1
  endwhile

  return [l:last_diff_line, l:j, (lsp#utils#count_utf16_code_units(l:old_line) - l:offset) + l:start_offset]
endfunction

function! lsp#utils#diff#extract_text(new_lines, start_line, start_char, end_line, end_char) abort
  if len(a:new_lines) == 0
     return ''
  endif

  let l:adj_end_line = len(a:new_lines) + a:end_line

  if a:start_line == l:adj_end_line
    let l:line = a:new_lines[a:start_line]
    let l:adj_end_char = (strchars(l:line) + a:end_char) + 1
    return strcharpart(l:line, a:start_char, l:adj_end_char - a:start_char)
  endif

  let l:result = strcharpart(a:new_lines[a:start_line], a:start_char) . "\n"
  for l:line in a:new_lines[a:start_line + 1 : a:end_line - 1]
    let l:result .= l:line . "\n"
  endfor
  if a:end_line != 0
    let l:line = a:new_lines[a:end_line]
    let l:length = strchars(l:line) + a:end_char + 1
    let l:result .= strcharpart(l:line, 0, l:length)
  endif
  return l:result
endfunction

function! lsp#utils#diff#length(old_lines, start_line, start_char, end_line, end_char) abort
  if len(a:old_lines) == 0
     return 0
  endif

  let l:adj_end_line = len(a:old_lines) + a:end_line
  if l:adj_end_line >= len(a:old_lines)
    let l:adj_end_char = a:end_char + 1
  else
    let l:adj_end_char = strchars(a:old_lines[l:adj_end_line]) + a:end_char + 1
  endif

  if a:start_line == l:adj_end_line
    return lsp#utils#count_utf16_code_units(strcharpart(a:old_lines[a:start_line], a:start_char, l:adj_end_char - a:start_char))
  endif

  let l:result = lsp#utils#count_utf16_code_units(strcharpart(a:old_lines[a:start_line], a:start_char)) + 1
  for l:line in a:old_lines[a:start_line + 1 : l:adj_end_line - 1]
    let l:result += lsp#utils#count_utf16_code_units(l:line) + 1
  endfor
  let l:result += lsp#utils#count_utf16_code_units(strcharpart(a:old_lines[l:adj_end_line], 0, l:adj_end_char))
  return l:result
endfunction

