" vint: -ProhibitUnusedVariable

"
" @param option = {
"   sync: v:true | v:false = Specify enable synchronous request.
" }
"

function! s:echo(...) abort
    echom json_encode(a:000)
endfunction

function! lsp#ui#vim#code_lens#do(option) abort
    let l:sync = get(a:option, 'sync', v:false)

    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_code_lens_provider(v:val)')
    if len(l:servers) == 0
        return lsp#utils#error('Code lens not supported for ' . &filetype)
    endif

    " TODO: cancel if there is a new command
    call lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#callbag#pipe(
        \       lsp#request(server, {
        \           'method': 'textDocument/codeLens',
        \           'params': {
        \               'textDocument': lsp#get_text_document_identifier(),
        \           },
        \       }),
        \       lsp#callbag#flatMap({x->s:resolve_if_required(server, x['response'])}),
        \   )
        \ }),
        \ lsp#callbag#tap({x->s:echo(x)}),
        \ lsp#callbag#subscribe(),
        \ )

    " let l:ctx = {
    " \ 'count': len(l:server_names),
    " \ 'results': [],
    " \}
    " let l:bufnr = bufnr('%')
    " let l:command_id = lsp#_new_command()
    " for l:server_name in l:server_names
    "     call lsp#send_request(l:server_name, {
    "         \ 'method': 'textDocument/codeLens',
    "         \ 'params': {
    "         \   'textDocument': lsp#get_text_document_identifier(),
    "         \ },
    "         \ 'sync': l:sync,
    "         \ 'on_notification': function('s:handle_code_lens', [l:ctx, l:server_name, l:command_id, l:sync, l:bufnr]),
    "         \ })
    " endfor
    " echo 'Retrieving code lenses ...'
endfunction

function! s:resolve_if_required(server, response) abort
    let l:codelens = a:response['result']
    if empty(l:codelens)
        return lsp#callbag#empty()
    endif

    return lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:codelens),
        \ )
    " return lsp#callbag#of({ 'server': a:server, 'response': a:response })
endfunction

function! s:handle_code_lens(ctx, server_name, command_id, sync, bufnr, data) abort
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

    let l:total_code_lenses = []
    for l:result in a:ctx['results']
        let l:server_name = l:result['server_name']
        let l:data = l:result['data']
        " Check response error.
        if lsp#client#is_error(l:data['response'])
            call lsp#utils#error('Failed to CodeLens for ' . l:server_name . ': ' . lsp#client#error_message(l:data['response']))
            continue
        endif

        " Check code lenses.
        let l:code_lenses = l:data['response']['result']
        if empty(l:code_lenses)
            continue
        endif

        for l:code_lens in l:code_lenses
            call add(l:total_code_lenses, {
            \    'server_name': l:server_name,
            \    'code_lens': l:code_lens,
            \})
        endfor
    endfor

    if len(l:total_code_lenses) == 0
        echo 'No code lenses found'
        return
    endif
    call lsp#log('s:handle_code_lens', l:total_code_lenses)

    echom json_encode(l:total_code_lenses)

    " " Prompt to choose code lenses.
    " let l:index = inputlist(map(copy(l:total_code_lenses), { i, lens ->
    "             \   printf('%s - [%s] %s', i + 1, lens['server_name'], lens['code_lens']['command']['title'])
    "             \ }))

    " " Execute code lens.
    " if 0 < l:index && l:index <= len(l:total_code_lenses)
    "     let l:selected = l:total_code_lenses[l:index - 1]
    "     call s:handle_one_code_lens(l:selected['server_name'], a:sync, a:bufnr, l:selected['code_lens'])
    " endif
endfunction

function! s:handle_one_code_lens(server_name, sync, bufnr, code_lens) abort
    call lsp#ui#vim#execute_command#_execute({
    \   'server_name': a:server_name,
    \   'command_name': get(a:code_lens['command'], 'command', ''),
    \   'command_args': get(a:code_lens['command'], 'arguments', v:null),
    \   'sync': a:sync,
    \   'bufnr': a:bufnr,
    \ })
endfunction
