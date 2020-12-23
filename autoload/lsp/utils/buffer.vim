let s:fixendofline_exists = exists('+fixendofline')

function! s:get_fixendofline(buf) abort
    let l:eol = getbufvar(a:buf, '&endofline')
    let l:binary = getbufvar(a:buf, '&binary')

    if s:fixendofline_exists
        let l:fixeol = getbufvar(a:buf, '&fixendofline')

        if !l:binary
            " When 'binary' is off and 'fixeol' is on, 'endofline' is not used
            "
            " When 'binary' is off and 'fixeol' is off, 'endofline' is used to
            " remember the presence of a <EOL>
            return l:fixeol || l:eol
        else
            " When 'binary' is on, the value of 'fixeol' doesn't matter
            return l:eol
        endif
    else
        " When 'binary' is off the value of 'endofline' is not used
        "
        " When 'binary' is on 'endofline' is used to remember the presence of
        " a <EOL>
        return !l:binary || l:eol
    endif
endfunction

function! lsp#utils#buffer#_get_fixendofline(bufnr) abort
    return s:get_fixendofline(a:bufnr)
endfunction

function! lsp#utils#buffer#_get_lines(buf) abort
    let l:lines = getbufline(a:buf, 1, '$')
    if s:get_fixendofline(a:buf)
        let l:lines += ['']
    endif
    return l:lines
endfunction

" @params {location} = {
"   'uri': 'file://....',
"   'range': {
"       'start': { 'line': 1, 'character': 1 },
"       'end': { 'line': 1, 'character': 1 },
"   }
" }
function! lsp#utils#buffer#_open_lsp_location(location) abort
    let l:path = lsp#utils#uri_to_path(a:location['uri'])
    let l:bufnr = bufnr(l:path)

    let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim(l:bufnr, a:location['range']['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim(l:bufnr, a:location['range']['end'])

    normal! m'
    if &modified && !&hidden
        let l:cmd = l:bufnr !=# -1 ? 'sb ' . l:bufnr : 'split ' . fnameescape(l:path)
    else
        let l:cmd = l:bufnr !=# -1 ? 'b ' . l:bufnr : 'edit ' . fnameescape(l:path)
    endif
    execute l:cmd . ' | call cursor('.l:start_line.','.l:start_col.')'

    normal! V
    call setpos("'<", [l:bufnr, l:start_line, l:start_col])
    call setpos("'>", [l:bufnr, l:end_line, l:end_col])
endfunction

function! lsp#utils#buffer#get_indent_size(bufnr) abort
    let l:shiftwidth = getbufvar(a:bufnr, '&shiftwidth')
    if getbufvar(a:bufnr, '&shiftwidth')
        return l:shiftwidth
    endif
    return getbufvar(a:bufnr, '&tabstop')
endfunction
