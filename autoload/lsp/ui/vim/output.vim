function! lsp#ui#vim#output#preview(data) abort
    if has('patch-8.1.1517')
        let l:winid = popup_atcursor('...', {
        \  'moved': 'any',
		\  'border': [1, 1, 1, 1],
		\})
        let l:buf = winbufnr(l:winid)
        let [l:ft, l:lines] = s:tolines(a:data)
        call setbufline(l:buf, 1, split(l:lines, "\n"))
        call win_execute(l:winid, 'setlocal filetype=' . l:ft . '.lsp-hover')
    else
        " Close any previously opened preview window
        pclose

        let l:current_window_id = win_getid()

        execute &previewheight.'new'

        let [l:ft, l:lines] = s:tolines(a:data)
        call setline(1, split(l:lines, "\n"))

        setlocal readonly nomodifiable

        let &l:filetype = l:ft . '.lsp-hover'

        if g:lsp_preview_keep_focus
          " restore focus to the previous window
          call win_gotoid(l:current_window_id)
        endif

        echo ''
    endif

    return ''
endfunction

function! s:tolines(data) abort
    if type(a:data) == type([])
        let l:lines = ''
        for l:entry in a:data
            let l:lines .= s:tolines(l:entry)[1] . "\n"
        endfor
        return ['markdown', l:lines]
    elseif type(a:data) == type('')
        return ['markdown', a:data]
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        return ['markdown', '```' . a:data.language . "\n" . a:data.value . "\n```\n"]
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        return [a:data.kind ==? 'plaintext' ? 'text' : a:data.kind, a:data.value]
    endif
    return ['', '']
endfunction
