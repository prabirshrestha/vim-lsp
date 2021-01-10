" https://microsoft.github.io/language-server-protocol/specification#workspace_symbol
" options - {
"   bufnr: bufnr('%')       " optional
"   server - 'server_name'  " optional
"   query: ''               " optional
" }
function! lsp#internal#workspace_symbol#search#do(options) abort
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    endif

    if len(l:servers) == 0
        echom 'textDocument/workspaceSymbol not supported'
        call lsp#utils#error('textDocument/workspaceSymbol not supported')
        return
    endif

    redraw | echo 'Retrieving workspace symbols ...'

    let l:TextChangeSubject = lsp#callbag#makeSubject()

    " use callbag debounce instead of quickpick debounce
    call lsp#internal#ui#quickpick#open({
        \ 'items': [],
        \ 'input': get(a:options, 'query', ''),
        \ 'key': 'text',
        \ 'debounce': 0,
        \ 'on_change': function('s:on_change', [l:TextChangeSubject]),
        \ 'on_accept': function('s:on_accept'),
        \ 'on_close': function('s:on_close'),
        \ })

    let s:Dispose = lsp#callbag#pipe(
        \ l:TextChangeSubject,
        \ lsp#callbag#debounceTime(250),
        \ lsp#callbag#distinctUntilChanged(),
        \ lsp#callbag#switchMap({query->
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromList(l:servers),
        \       lsp#callbag#tap({_->lsp#internal#ui#quickpick#busy(1)}),
        \       lsp#callbag#flatMap({server->
        \           lsp#callbag#pipe(
        \               lsp#request(server, {
        \                   'method': 'workspace/symbol',
        \                   'params': {
        \                       'query': query
        \                   }
        \               }),
        \               lsp#callbag#map({x->{'server': server, 'request': x['request'], 'response': x['response']}}),
        \          )
        \       }),
        \       lsp#callbag#scan({acc, curr->add(acc, curr)}, []),
        \       lsp#callbag#tap({x->s:update_ui_items(x)}),
        \       lsp#callbag#tap({'complete': {->lsp#internal#ui#quickpick#busy(0)}}),
        \   )
        \ }),
        \ lsp#callbag#subscribe({
        \   'error': {e->s:on_error(e)},
        \ }),
        \ )
    " Notify empty query. Some servers may not return results when query is empty
    call l:TextChangeSubject(1, '')
endfunction

function! s:on_change(TextChangeSubject, data, ...) abort
    call a:TextChangeSubject(1, a:data['input'])
endfunction

function! s:update_ui_items(x) abort
    let l:items = []
    for l:i in a:x
        let l:items += lsp#ui#vim#utils#symbols_to_loc_list(l:i['server'], l:i)
    endfor
    call lsp#internal#ui#quickpick#items(l:items)
endfunction

function! s:on_accept(data, name) abort
    call lsp#internal#ui#quickpick#close()
    call lsp#utils#location#_open_vim_list_item(a:data['items'][0], '')
endfunction

function! s:on_close(...) abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:on_error(e) abort
    call lsp#internal#ui#quickpick#close()
    call lsp#log('LspWorkspaceSymbolSearch error', a:e)
endfunction
