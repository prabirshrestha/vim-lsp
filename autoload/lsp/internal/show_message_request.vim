function! lsp#internal#show_message_request#_enable()
    if !g:lsp_show_message_request_enable | return | endif
    let s:Dispose = lsp#callbag#pipe(
            \ lsp#stream(),
            \ lsp#callbag#filter({_->g:lsp_show_message_request_enable}),
            \ lsp#callbag#filter({x->
            \   has_key(x, 'server') &&
            \   has_key(x, 'request') && !lsp#client#is_error(x['request']) &&
            \   has_key(x['request'], 'method') && x['request']['method'] ==# 'window/showMessageRequest'
            \ }),
            \ lsp#callbag#map({x->s:show_message_request(x['server'], x['request'])}),
            \ lsp#callbag#map({x->s:send_message_response(x['server'], x['request'], x['selected_action'])}),
            \ lsp#callbag#flatten(),
            \ lsp#callbag#subscribe({
            \   'error': function('s:on_error'),
            \ }),
            \ )
    endfunction

    function! lsp#internal#show_message_request#_disable()
        if exists('s:Dispose')
            call s:Dispose()
            unlet s:Dispose
        endif
    endfunction

    function! s:on_error(e) abort
        call lsp#log('lsp#internal#show_message_request error', a:e)
        if exists('s:Dispose')
            call s:Dispose()
            unlet s:Dispose
        endif
    endfunction

    function! s:show_message_request(server_name, request) abort
        let l:params = a:request['params']

        let l:selected_action = v:null

        if has_key(l:params, 'actions') && !empty(l:params['actions'])
            echom l:params['message']
            let l:index = inputlist(map(copy(l:params['actions']), {i, action ->
            \ printf('%d - [%s] %s', i + 1, a:server_name, action['title'])
            \ }))
        if l:index > 0 && l:index <= len(l:index)
            let l:selected_action = l:params['actions'][l:index - 1]
        endif
    else
        echom l:params['message']
    endif

    return { 'server': a:server_name, 'request': a:request, 'selected_action': l:selected_action }
endfunction

function! s:send_message_response(server_name, request, selected_action)
    return lsp#request(a:server_name, {
        \ 'id': a:request['id'],
        \ 'result': a:selected_action
        \})
endfunction
