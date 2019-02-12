function! lsp#utils#buffer#_get_lines(buf) abort
    let l:lines = getbufline(a:buf, 1, '$')
    if getbufvar(a:buf, '&fixendofline')
        let l:lines += ['']
    endif
    return l:lines
endfunction
