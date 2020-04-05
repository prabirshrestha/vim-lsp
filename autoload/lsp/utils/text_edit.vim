function! lsp#utils#text_edit#apply_text_edits(uri, text_edits) abort
    let l:current_bufname = bufname('%')
    let l:target_bufname = lsp#utils#uri_to_path(a:uri)
    let l:cursor_position = lsp#get_position()
    let l:cursor_offset = 0
    let l:topline = line('w0')

    call s:_switch(l:target_bufname)
    for l:text_edit in s:_normalize(a:text_edits)
        let l:cursor_offset += s:_apply(bufnr(l:target_bufname), l:text_edit, l:cursor_position)
    endfor
    call s:_switch(l:current_bufname)

    if bufnr(l:current_bufname) == bufnr(l:target_bufname)
        call cursor(lsp#utils#position#lsp_to_vim('%', l:cursor_position))
        call winrestview({ 'topline': l:topline + l:cursor_offset })
    endif
endfunction

"
" _apply
"
function! s:_apply(bufnr, text_edit, cursor_position) abort
  " create before/after line.
  let l:start_line = getline(a:text_edit.range.start.line + 1)
  let l:end_line = getline(a:text_edit.range.end.line + 1)
  let l:before_line = strcharpart(l:start_line, 0, a:text_edit.range.start.character)
  let l:after_line = strcharpart(l:end_line, a:text_edit.range.end.character, strchars(l:end_line) - a:text_edit.range.end.character)

  " create new lines.
  let l:new_lines = lsp#utils#_split_by_eol(a:text_edit.newText)
  let l:new_lines[0] = l:before_line . l:new_lines[0]
  let l:new_lines[-1] = l:new_lines[-1] . l:after_line

  " fixendofline
  let l:buffer_length = len(getbufline(a:bufnr, '^', '$'))
  let l:should_fixendofline = lsp#utils#buffer#_get_fixendofline(a:bufnr)
  let l:should_fixendofline = l:should_fixendofline && l:new_lines[-1] ==# ''
  let l:should_fixendofline = l:should_fixendofline && l:buffer_length <= a:text_edit['range']['end']['line']
  let l:should_fixendofline = l:should_fixendofline && a:text_edit['range']['end']['character'] == 0
  if l:should_fixendofline
      call remove(l:new_lines, -1)
  endif

  let l:new_lines_len = len(l:new_lines)

  " fix cursor col
  if a:text_edit.range.end.line == a:cursor_position.line
      if a:text_edit.range.end.character <= a:cursor_position.character
          let l:end_character = strchars(l:new_lines[-1]) - strchars(l:after_line)
          let l:end_offset = a:cursor_position.character - a:text_edit.range.end.character
          let a:cursor_position.character = l:end_character + l:end_offset
      endif
  endif

  " fix cursor line
  let l:cursor_offset = 0
  if a:text_edit.range.end.line <= a:cursor_position.line
      let l:cursor_offset = l:new_lines_len - (a:text_edit.range.end.line - a:text_edit.range.start.line) - 1
      let a:cursor_position.line += l:cursor_offset
  endif

  " append new lines.
  call append(a:text_edit.range.start.line, l:new_lines)

  " remove old lines
  execute printf('%s,%sdelete _',
  \   l:new_lines_len + a:text_edit.range.start.line + 1,
  \   min([l:new_lines_len + a:text_edit.range.end.line + 1, line('$')])
  \ )

  return l:cursor_offset
endfunction

"
" _normalize
"
function! s:_normalize(text_edits) abort
  let l:text_edits = type(a:text_edits) == type([]) ? a:text_edits : [a:text_edits]
  let l:text_edits = filter(copy(l:text_edits), { _, text_edit -> type(text_edit) == type({}) })
  let l:text_edits = s:_range(l:text_edits)
  let l:text_edits = sort(copy(l:text_edits), function('s:_compare', [], {}))
  let l:text_edits = s:_check(l:text_edits)
  return reverse(l:text_edits)
endfunction

"
" _range
"
function! s:_range(text_edits) abort
  for l:text_edit in a:text_edits
    if l:text_edit.range.start.line > l:text_edit.range.end.line || (
          \   l:text_edit.range.start.line == l:text_edit.range.end.line &&
          \   l:text_edit.range.start.character > l:text_edit.range.end.character
          \ )
      let l:text_edit.range = { 'start': l:text_edit.range.end, 'end': l:text_edit.range.start }
    endif
  endfor
  return a:text_edits
endfunction

"
" _check
"
" LSP Spec says `multiple text edits can not overlap those ranges`.
" This function check it. But does not throw error.
"
function! s:_check(text_edits) abort
  if len(a:text_edits) > 1
    let l:range = a:text_edits[0].range
    for l:text_edit in a:text_edits[1 : -1]
      if l:range.end.line > l:text_edit.range.start.line || (
      \   l:range.end.line == l:text_edit.range.start.line &&
      \   l:range.end.character > l:text_edit.range.start.character
      \ )
        call lsp#log('text_edit: range overlapped.')
      endif
      let l:range = l:text_edit.range
    endfor
  endif
  return a:text_edits
endfunction

"
" _compare
"
function! s:_compare(text_edit1, text_edit2) abort
  let l:diff = a:text_edit1.range.start.line - a:text_edit2.range.start.line
  if l:diff == 0
    return a:text_edit1.range.start.character - a:text_edit2.range.start.character
  endif
  return l:diff
endfunction

"
" _switch
"
function! s:_switch(path) abort
  if bufnr(a:path) >= 0
    execute printf('keepalt keepjumps %sbuffer!', bufnr(a:path))
  else
    execute printf('keepalt keepjumps edit! %s', fnameescape(a:path))
  endif
endfunction

