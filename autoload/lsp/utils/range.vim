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

" Convert a LSP range to one or more vim match positions.
" If the range spans over multiple lines, break it down to multiple
" positions, one for each line.
" Return a list of positions.
function! lsp#utils#range#lsp_to_vim(bufnr, range) abort
    let l:position = []

    let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim(a:bufnr, a:range['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim(a:bufnr, a:range['end'])
    if l:end_line == l:start_line
        let l:position = [[
        \ l:start_line,
        \ l:start_col,
        \ l:end_col - l:start_col
        \ ]]
    else
        " First line
        let l:position = [[
        \ l:start_line,
        \ l:start_col,
        \ 999
        \ ]]

        " Last line
        call add(l:position, [
        \ l:end_line,
        \ 1,
        \ l:end_col
        \ ])

        " Lines in the middle
        let l:middle_lines = map(
        \ range(l:start_line + 1, l:end_line - 1),
        \ {_, l -> [l, 0, 999]}
        \ )

        call extend(l:position, l:middle_lines)
    endif

    return l:position
endfunction
