" vint: -ProhibitUnusedVariable

function! lsp#ui#vim#code_action#complete(input, command, len) abort
    let l:server_names = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_code_action_provider(v:val)')
    let l:kinds = []
    for l:server_name in l:server_names
        let l:kinds += lsp#capabilities#get_code_action_kinds(l:server_name)
    endfor
    return filter(copy(l:kinds), { _, kind -> kind =~ '^' . a:input })
endfunction

"
" @param option = {
"   selection: v:true | v:false = Provide by CommandLine like `:'<,'>LspCodeAction`
"   sync: v:true | v:false      = Specify enable synchronous request. Example use case is `BufWritePre`
"   query_filter: v:false | (action) => (v:true | v:false)
"                               = Specify code action query filter. If query filter provided and then filtered code action is only one, invoke code action immediately.
" }
"
function! lsp#ui#vim#code_action#do(option) abort
    let l:selection = get(a:option, 'selection', v:false)
    let l:sync = get(a:option, 'sync', v:false)
    let l:Query_filter = get(a:option, 'query_filter', v:false)

    let l:server_names = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_code_action_provider(v:val)')
    if len(l:server_names) == 0
        return lsp#utils#error('Code action not supported for ' . &filetype)
    endif

    if l:selection
        let l:range = lsp#utils#range#_get_recent_visual_range()
    else
        let l:range = lsp#utils#range#_get_current_line_range()
    endif

    let l:ctx = {
    \ 'count': len(l:server_names),
    \ 'results': [],
    \}
    let l:bufnr = bufnr('%')
    let l:command_id = lsp#_new_command()
    for l:server_name in l:server_names
        let l:diagnostic = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor(l:server_name)
        call lsp#send_request(l:server_name, {
                    \ 'method': 'textDocument/codeAction',
                    \ 'params': {
                    \   'textDocument': lsp#get_text_document_identifier(),
                    \   'range': empty(l:diagnostic) || l:selection ? l:range : l:diagnostic['range'],
                    \   'context': {
                    \       'diagnostics' : empty(l:diagnostic) ? [] : [l:diagnostic],
                    \       'only': ['', 'quickfix', 'refactor', 'refactor.extract', 'refactor.inline', 'refactor.rewrite', 'source', 'source.organizeImports'],
                    \   },
                    \ },
                    \ 'sync': l:sync,
                    \ 'on_notification': function('s:handle_code_action', [l:ctx, l:server_name, l:command_id, l:sync, l:Query_filter, l:bufnr]),
                    \ })
    endfor
    echo 'Retrieving code actions ...'
endfunction

function! s:handle_code_action(ctx, server_name, command_id, sync, query_filter, bufnr, data) abort
    " Ignore old request.
    if a:command_id != lsp#_last_command()
        return
    endif

    call add(a:ctx['results'], {
    \    'server_name': a:server_name,
    \    'data': a:data,
    \})
    let a:ctx['count'] -= 1
    if a:ctx['count'] ># 0
        return
    endif

    let l:total_code_actions = []
    for l:result in a:ctx['results']
        let l:server_name = l:result['server_name']
        let l:data = l:result['data']
        " Check response error.
        if lsp#client#is_error(l:data['response'])
            call lsp#utils#error('Failed to CodeAction for ' . l:server_name . ': ' . lsp#client#error_message(l:data['response']))
            continue
        endif

        " Check code actions.
        let l:code_actions = l:data['response']['result']

        " Filter code actions.
        if !empty(a:query_filter)
            let l:code_actions = filter(l:code_actions, { _, action -> a:query_filter(action) })
        endif
        if empty(l:code_actions)
            continue
        endif

        for l:code_action in l:code_actions
            call add(l:total_code_actions, {
            \    'server_name': l:server_name,
            \    'code_action': l:code_action,
            \})
        endfor
    endfor

    if len(l:total_code_actions) == 0
        echo 'No code actions found'
        return
    endif
    call lsp#log('s:handle_code_action', l:total_code_actions)

    " Prompt to choose code actions when empty query filter provided.
    let l:index = 1
    if len(l:total_code_actions) > 1 || empty(a:query_filter)
        let l:index = inputlist(map(copy(l:total_code_actions), { i, action ->
                    \   printf('%s - [%s] %s', i + 1, action['server_name'], action['code_action']['title'])
                    \ }))
    endif

    " Execute code action.
    if 0 < l:index && l:index <= len(l:total_code_actions)
        let l:selected = l:total_code_actions[l:index - 1]
        call s:handle_one_code_action(l:selected['server_name'], a:sync, a:bufnr, l:selected['code_action'])
    endif
endfunction

function! s:handle_one_code_action(server_name, sync, bufnr, command_or_code_action) abort
    " has WorkspaceEdit.
    if has_key(a:command_or_code_action, 'edit')
        call lsp#utils#workspace_edit#apply_workspace_edit(a:command_or_code_action['edit'])
    endif

    " Command.
    if has_key(a:command_or_code_action, 'command') && type(a:command_or_code_action['command']) == type('')
        call lsp#ui#vim#execute_command#_execute({
        \   'server_name': a:server_name,
        \   'command_name': get(a:command_or_code_action, 'command', ''),
        \   'command_args': get(a:command_or_code_action, 'arguments', v:null),
        \   'sync': a:sync,
        \   'bufnr': a:bufnr,
        \ })

    " has Command.
    elseif has_key(a:command_or_code_action, 'command') && type(a:command_or_code_action['command']) == type({})
        call lsp#ui#vim#execute_command#_execute({
        \   'server_name': a:server_name,
        \   'command_name': get(a:command_or_code_action['command'], 'command', ''),
        \   'command_args': get(a:command_or_code_action['command'], 'arguments', v:null),
        \   'sync': a:sync,
        \   'bufnr': a:bufnr,
        \ })
    endif
endfunction

