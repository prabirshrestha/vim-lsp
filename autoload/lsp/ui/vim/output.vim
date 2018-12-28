function! lsp#ui#vim#output#preview(data) abort
    " Close any previously opened preview window
    pclose

    let l:current_window_id = win_getid()

    execute &previewheight.'new'

    let l:ft = s:append(a:data)
    " Delete first empty line
    0delete

    setlocal readonly nomodifiable

    let &l:filetype = l:ft . '.lsp-hover'

    if g:lsp_preview_keep_focus
      " restore focus to the previous window
      call win_gotoid(l:current_window_id)
    endif

    echo ''

    return ''
endfunction

function! s:append(data) abort
    if type(a:data) == type([])
        for l:entry in a:data
            call s:append(entry)
        endfor

        return 'markdown'
    elseif type(a:data) == type('')
        silent put =a:data

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        silent put ='```'.a:data.language
        silent put =a:data.value
        silent put ='```'

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        silent put =a:data.value

        return a:data.kind ==? 'plaintext' ? 'text' : a:data.kind
    endif
endfunction
