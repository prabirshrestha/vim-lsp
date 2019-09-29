let s:fixendofline_exists = exists('+fixendofline')

function! lsp#utils#buffer#get_fixendofline(buf) abort
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

function! lsp#utils#buffer#_get_lines(buf) abort
    let l:lines = getbufline(a:buf, 1, '$')
    if lsp#utils#buffer#get_fixendofline(a:buf)
        let l:lines += ['']
    endif
    return l:lines
endfunction
