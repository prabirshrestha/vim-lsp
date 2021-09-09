" This function can be error prone if the caller forgets to use +1 to vim line
" so use lsp#utils#position#lsp_to_vim instead
" Convert a character-index (0-based) to byte-index (1-based)
" This function requires a buffer specifier (expr, see :help bufname()),
" a line number (lnum, 1-based), and a character-index (char, 0-based).
function! s:to_col(expr, lnum, char) abort
    let l:lines = getbufline(a:expr, a:lnum)
    if l:lines == []
        if type(a:expr) != v:t_string || !filereadable(a:expr)
            " invalid a:expr
            return a:char + 1
        endif
        " a:expr is a file that is not yet loaded as a buffer
        let l:lines = readfile(a:expr, '', a:lnum)
        if l:lines == []
            " when the file is empty. a:char should be 0 in the case
            return a:char + 1
        endif
    endif
    let l:linestr = l:lines[-1]
    return strlen(strcharpart(l:linestr, 0, a:char)) + 1
endfunction

" The inverse version of `s:to_col`.
" Convert [lnum, col] to LSP's `Position`.
function! s:to_char(expr, lnum, col) abort
    let l:lines = getbufline(a:expr, a:lnum)
    if l:lines == []
        if type(a:expr) != v:t_string || !filereadable(a:expr)
            " invalid a:expr
            return a:col - 1
        endif
        " a:expr is a file that is not yet loaded as a buffer
        let l:lines = readfile(a:expr, '', a:lnum)
    endif
    let l:linestr = l:lines[-1]
    return strchars(strpart(l:linestr, 0, a:col - 1))
endfunction

" @param expr = see :help bufname()
" @param position = {
"   'line': 1,
"   'character': 1
" }
" @returns [
"   line,
"   col
" ]
function! lsp#utils#position#lsp_to_vim(expr, position) abort
    let l:line = lsp#utils#position#lsp_line_to_vim(a:expr, a:position)
    let l:col = lsp#utils#position#lsp_character_to_vim(a:expr, a:position)
    return [l:line, l:col]
endfunction

" @param expr = see :help bufname()
" @param position = {
"   'line': 1,
"   'character': 1
" }
" @returns
"   line
function! lsp#utils#position#lsp_line_to_vim(expr, position) abort
    return a:position['line'] + 1
endfunction

" @param expr = see :help bufname()
" @param position = {
"   'line': 1,
"   'character': 1
" }
" @returns
"   line
function! lsp#utils#position#lsp_character_to_vim(expr, position) abort
    let l:line = a:position['line'] + 1 " optimize function overhead by not calling lsp_line_to_vim
    let l:char = a:position['character']
    return s:to_col(a:expr, l:line, l:char)
endfunction

" @param expr = :help bufname()
" @param pos = [lnum, col]
" @returns {
"   'line': line,
"   'character': character
" }
function! lsp#utils#position#vim_to_lsp(expr, pos) abort
    return {
         \   'line': a:pos[0] - 1,
         \   'character': s:to_char(a:expr, a:pos[0], a:pos[1])
         \ }
endfunction

