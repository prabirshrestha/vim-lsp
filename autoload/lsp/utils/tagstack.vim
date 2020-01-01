if exists('*gettagstack') && exists('*settagstack')
    function! lsp#utils#tagstack#_update() abort
        let l:bufnr = bufnr('%')
        let l:item = {'bufnr': l:bufnr, 'from': [l:bufnr, line('.'), col('.'), 0], 'tagname': expand('<cword>')}
        let l:winid = win_getid()

        let l:stack = gettagstack(l:winid)
        if l:stack['length'] == l:stack['curidx']
            " Replace the last items with item.
            let l:action = 'r'
            let l:stack['items'][l:stack['curidx']-1] = l:item
        elseif l:stack['length'] > l:stack['curidx']
            " Replace items after used items with item.
            let l:action = 'r'
            if l:stack['curidx'] > 1
                let l:stack['items'] = add(l:stack['items'][:l:stack['curidx']-2], l:item)
            else
                let l:stack['items'] = [l:item]
            endif
        else
            " Append item.
            let l:action = 'a'
            let l:stack['items'] = [l:item]
        endif
        let l:stack['curidx'] += 1

        call settagstack(l:winid, l:stack, l:action)
    endfunction
else
    function! lsp#utils#tagstack#_update() abort
        " do nothing
    endfunction
endif
