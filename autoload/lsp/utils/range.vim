"
" Returns recent visual-mode range.
"
function! lsp#utils#range#_get_recent_visual_range() abort
    let l:start_pos = getpos("'<")[1 : 2]
    let l:end_pos = getpos("'>")[1 : 2]
    let l:end_pos[1] += 1 " To exclusive

    " Fix line selection.
    let l:end_line = getline(l:end_pos[0])
    if l:end_pos[1] > strlen(l:end_line)
        let l:end_pos[1] = strlen(l:end_line) + 1
    endif

    let l:range = {}
    let l:range['start'] = lsp#utils#position#vim_to_lsp('%', l:start_pos)
    let l:range['end'] = lsp#utils#position#vim_to_lsp('%', l:end_pos)
    return l:range
endfunction

"
" Returns current line range.
"
function! lsp#utils#range#_get_current_line_range() abort
  let l:pos = getpos('.')[1 : 2]
  let l:range = {}
  let l:range['start'] = lsp#utils#position#vim_to_lsp('%', l:pos)
  let l:range['end'] = lsp#utils#position#vim_to_lsp('%', [l:pos[0], l:pos[1] + strlen(getline(l:pos[0])) + 1])
  return l:range
endfunction

