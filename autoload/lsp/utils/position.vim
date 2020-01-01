" @param bufnr = bufnr
" @param position = {
"   'line': 1,
"   'character': 1
" }
" @returns [
"   line,
"   col
" ]
function! lsp#utils#position#_lsp_to_vim(expr, position) abort
    let l:line = a:position['line'] + 1
    let l:char = a:position['character']
    let l:col = lsp#utils#to_col(a:expr, l:line, l:char)
    return [l:line, l:col]
endfunction
