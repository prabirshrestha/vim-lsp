function! lsp#ui#vim#output#preview(data) abort
    " Close any previously opened preview window
    pclose

    execute &previewheight.'new'

    let l:ft = s:append(a:data)
    " Delete first empty line
    0delete

    setlocal readonly nomodifiable

    let &l:filetype = l:ft . '.lsp-hover'

    return ''
endfunction

function! s:append(data) abort
    if type(a:data) == type([])
        for l:entry in a:data
            call s:append(entry)
        endfor

        return 'markdown'
    elseif type(a:data) == type('')
        put =a:data

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        put ='```'.a:data.language
        put =a:data.value
        put ='```'

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        put =a:data.value

        return a:data.kind == 'plaintext' ? 'text' : a:data.kind
    endif
endfunction
