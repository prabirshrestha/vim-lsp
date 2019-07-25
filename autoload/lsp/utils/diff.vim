" This is copied from https://github.com/natebosch/vim-lsc/blob/master/autoload/lsc/diff.vim
"
" Computes a simplistic diff between [old] and [new].
"
" Returns a dict with keys `range`, `rangeLength`, and `text` matching the LSP
" definition of `TextDocumentContentChangeEvent`.
"
" Finds a single change between the common prefix, and common postfix.
function! lsp#utils#diff#compute(old, new) abort
  let [start_line, start_char] = s:FirstDifference(a:old, a:new)
  let [end_line, end_char] =
      \ s:LastDifference(a:old[start_line :], a:new[start_line :], start_char)

  let text = s:ExtractText(a:new, start_line, start_char, end_line, end_char)
  let length = s:Length(a:old, start_line, start_char, end_line, end_char)

  let adj_end_line = len(a:old) + end_line
  let adj_end_char = end_line == 0 ? 0 : strchars(a:old[end_line]) + end_char + 1

  let result = { 'range': {'start': {'line': start_line, 'character': start_char},
      \ 'end': {'line': adj_end_line, 'character': adj_end_char}},
      \ 'text': text,
      \ 'rangeLength': length,
      \}

  return result
endfunction

" Finds the line and character of the first different character between two
" list of Strings.
function! s:FirstDifference(old, new) abort
  let line_count = min([len(a:old), len(a:new)])
  if line_count == 0 | return [0, 0] | endif
  let i = 0
  while i < line_count
    if a:old[i] !=# a:new[i] | break | endif
    let i += 1
  endwhile
  if i >= line_count
    return [line_count - 1, strchars(a:old[line_count - 1])]
  endif
  let old_line = a:old[i]
  let new_line = a:new[i]
  let length = min([strchars(old_line), strchars(new_line)])
  let j = 0
  while j < length
    if strgetchar(old_line, j) != strgetchar(new_line, j) | break | endif
    let j += 1
  endwhile
  return [i, j]
endfunction

function! s:LastDifference(old, new, start_char) abort
  let line_count = min([len(a:old), len(a:new)])
  if line_count == 0 | return [0, 0] | endif
  let i = -1
  while i >= -1 * line_count
    if a:old[i] !=# a:new[i] | break | endif
    let i -= 1
  endwhile
  if i <= -1 * line_count
    let i = -1 * line_count
    let old_line = strcharpart(a:old[i], a:start_char)
    let new_line = strcharpart(a:new[i], a:start_char)
  else
    let old_line = a:old[i]
    let new_line = a:new[i]
  endif
  let old_line_length = strchars(old_line)
  let new_line_length = strchars(new_line)
  let length = min([old_line_length, new_line_length])
  let j = -1
  while j >= -1 * length
    if  strgetchar(old_line, old_line_length + j) !=
        \ strgetchar(new_line, new_line_length + j)
      break
    endif
    let j -= 1
  endwhile
  return [i, j]
endfunction

function! s:ExtractText(lines, start_line, start_char, end_line, end_char) abort
  if a:start_line == len(a:lines) + a:end_line
    if a:end_line == 0 | return '' | endif
    let l:line = a:lines[a:start_line]
    let l:length = strchars(l:line) + a:end_char - a:start_char + 1
    return strcharpart(l:line, a:start_char, l:length)
  endif
  let result = strcharpart(a:lines[a:start_line], a:start_char)."\n"
  for line in a:lines[a:start_line + 1:a:end_line - 1]
    let result .= line."\n"
  endfor
  if a:end_line != 0
    let l:line = a:lines[a:end_line]
    let l:length = strchars(l:line) + a:end_char + 1
    let result .= strcharpart(l:line, 0, l:length)
  endif
  return result
endfunction

function! s:Length(lines, start_line, start_char, end_line, end_char) abort
  let adj_end_line = len(a:lines) + a:end_line
  if adj_end_line >= len(a:lines)
    let adj_end_char = a:end_char - 1
  else
    let adj_end_char = strchars(a:lines[adj_end_line]) + a:end_char
  endif
  if a:start_line == adj_end_line
    return adj_end_char - a:start_char + 1
  endif
  let result = strchars(a:lines[a:start_line]) - a:start_char + 1
  let line = a:start_line + 1
  while line < adj_end_line
    let result += strchars(a:lines[line]) + 1
    let line += 1
  endwhile
  let result += adj_end_char + 1
  return result
endfunction
