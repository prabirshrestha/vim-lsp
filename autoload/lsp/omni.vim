let s:complete_counter = 0

let s:completion_status_success = 'success'
let s:completion_status_failed = 'failed'
let s:completion_status_pending = 'pending'

let s:completion = {'status': '', 'matches': []}

function! lsp#omni#complete(findstart, base) abort
    let l:info = s:find_complete_servers_and_start_pos()

    if a:findstart
        if len(l:info['server_names']) == 0
            return -1
        endif

        if g:lsp_async_completion
            return col('.')
        else
            return l:info['findstart'] - 1
        endif
    else
        if len(l:info['server_names']) == 0
            return []
        endif

        if !g:lsp_async_completion
            let s:completion['status'] = s:completion_status_pending
        endif

        let s:complete_counter = s:complete_counter + 1
        let l:server_name = l:info['server_names'][0]
        " TODO: support multiple servers
        call lsp#send_request(l:server_name, {
            \ 'method': 'textDocument/completion',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_omnicompletion', [l:server_name, l:info['findstart'], s:complete_counter]),
            \ })
        if g:lsp_async_completion
            return []
        else
            while s:completion['status'] == s:completion_status_pending
                sleep 10m
            endwhile
            let s:completion['matches'] = filter(s:completion['matches'], {_, match -> match['word'] =~ '^' . a:base})
            let s:completion['status'] = ''
            return s:completion['matches']
    endif
endfunction

function! s:find_complete_servers_and_start_pos() abort
    let l:server_names = []
    for l:server_name in lsp#get_whitelisted_servers()
        let l:init_capabilities = lsp#get_server_capabilities(l:server_name)
        if has_key(l:init_capabilities, 'completionProvider')
            " TODO: support triggerCharacters
            call add(l:server_names, l:server_name)
        endif
    endfor

    let l:typed = strpart(getline('.'), 0, col('.') - 1)
    " TODO: allow user to customize refresh patterns
    let l:refresh_pattern = '\k\+$'
    let l:matchpos = lsp#utils#matchstrpos(l:typed, l:refresh_pattern)
    let l:startpos = l:matchpos[1]
    let l:endpos = l:matchpos[2]
    let l:typed_len = l:endpos - l:startpos
    let l:findstart = len(l:typed) - l:typed_len + 1

    return { 'findstart': l:findstart, 'server_names': l:server_names }
endfunction

function! s:handle_omnicompletion(server_name, startcol, complete_counter, data) abort
    if s:complete_counter != a:complete_counter
        " ignore old completion results
        return
    endif

    if lsp#client#is_error(a:data) || !has_key(a:data, 'response') || !has_key(a:data['response'], 'result')
        let s:completion['status'] = s:completion_status_failed
        return
    endif

    let l:result = a:data['response']['result']

    if type(l:result) == type([])
        let l:items = l:result
        let l:incomplete = 0
    else
        let l:items = l:result['items']
        let l:incomplete = l:result['isIncomplete']
    endif

    let l:matches = []
    let l:matches = map(l:items,'{"word":v:val["label"],"dup":1,"icase":1,"menu": ""}')
    if g:lsp_async_completion
        call complete(a:startcol, l:matches)
    else
        let s:completion['matches'] = l:matches
        let s:completion['status'] = s:completion_status_success
    endif
endfunction
