" This function can be error prone if the caller forgets to use +1 to vim line
" so use lsp#utils#position#_lsp_to_vim instead
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
function! lsp#utils#position#_lsp_to_vim(expr, position) abort
    let l:line = a:position['line'] + 1
    let l:char = a:position['character']
    let l:col = s:to_col(a:expr, l:line, l:char)
    return [l:line, l:col]
endfunction

" @param expr = :help bufname()
" @param pos = [lnum, col]
" @returns {
"   'line': line,
"   'character': character
" }
function! lsp#utils#position#_vim_to_lsp(expr, pos) abort
    return {
         \   'line': a:pos[0] - 1,
         \   'character': s:to_char(a:expr, a:pos[0], a:pos[1])
         \ }
endfunction

