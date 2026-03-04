" This function can be error prone if the caller forgets to use +1 to vim line
" so use lsp#utils#position#lsp_to_vim instead
" Convert a character-index (0-based) to byte-index (1-based)
" This function requires a buffer specifier (expr, see :help bufname()),
" a line number (lnum, 1-based), and a character-index (char, 0-based).
"
" When utf16idx()/byteidx() with UTF-16 support are available (Vim 9.0.1485+),
" the character-index is treated as a UTF-16 code unit offset, which is
" correct per the LSP specification. Otherwise falls back to Unicode
" codepoint counting.

function! s:_get_line(expr, lnum) abort
    let l:lines = getbufline(a:expr, a:lnum)
    if l:lines == []
        if type(a:expr) != v:t_string || !filereadable(a:expr)
            return []
        endif
        let l:lines = readfile(a:expr, '', a:lnum)
    endif
    return l:lines
endfunction

if exists('*utf16idx')
    function! s:to_col(expr, lnum, char) abort
        let l:lines = s:_get_line(a:expr, a:lnum)
        if l:lines == []
            return a:char + 1
        endif
        return byteidx(l:lines[-1], a:char, v:true) + 1
    endfunction

    function! s:to_char(expr, lnum, col) abort
        let l:lines = s:_get_line(a:expr, a:lnum)
        if l:lines == []
            return a:col - 1
        endif
        let l:linestr = l:lines[-1]
        let l:byteidx = a:col - 1
        if l:byteidx >= strlen(l:linestr)
            return utf16idx(l:linestr, strlen(l:linestr))
        endif
        let l:utf16 = utf16idx(l:linestr, l:byteidx)
        " If byteidx is in the middle of a multi-byte character, round up
        " to match the old strchars(strpart()) behavior
        let l:round_trip = byteidx(l:linestr, l:utf16, v:true)
        if l:round_trip >= 0 && l:round_trip < l:byteidx
            return l:utf16 + 1
        endif
        return l:utf16
    endfunction
else
    function! s:to_col(expr, lnum, char) abort
        let l:lines = s:_get_line(a:expr, a:lnum)
        if l:lines == []
            return a:char + 1
        endif
        return strlen(strcharpart(l:lines[-1], 0, a:char)) + 1
    endfunction

    function! s:to_char(expr, lnum, col) abort
        let l:lines = s:_get_line(a:expr, a:lnum)
        if l:lines == []
            return a:col - 1
        endif
        return strchars(strpart(l:lines[-1], 0, a:col - 1))
    endfunction
endif

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
