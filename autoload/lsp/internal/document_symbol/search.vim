" https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol
" options - {
"   bufnr: bufnr('%')       " optional
"   server - 'server_name'  " optional
" }
function! lsp#internal#document_symbol#search#do(options) abort
    let l:bufnr = get(a:options, 'bufnr', bufnr('%'))
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    endif

    if len(l:servers) == 0
        let l:filetype = getbufvar(l:bufnr, '&filetype')
        call lsp#utils#error('textDocument/documentSymbol not supported for ' . l:filetype)
        return
    endif

    redraw | echo 'Retrieving document symbols ...'

    call lsp#internal#ui#quickpick#open({
        \ 'items': [],
        \ 'busy': 1,
        \ 'input': '',
        \ 'key': 'text',
        \ 'on_accept': function('s:on_accept'),
        \ 'on_close': function('s:on_close'),
        \ })

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#callbag#pipe(
        \       lsp#request(server, {
        \           'method': 'textDocument/documentSymbol',
        \           'params': {
        \               'textDocument': lsp#get_text_document_identifier(l:bufnr),
        \           },
        \       }),
        \       lsp#callbag#map({x->{'server': server, 'request': x['request'], 'response': x['response']}}),
        \   )
        \ }),
        \ lsp#callbag#scan({acc, curr->add(acc, curr)}, []),
        \ lsp#callbag#tap({x->s:update_ui_items(x)}),
        \ lsp#callbag#subscribe({
        \   'complete':{->lsp#internal#ui#quickpick#busy(0)},
        \   'error':{e->s:on_error(e)},
        \ }),
        \ )
endfunction

function! s:update_ui_items(x) abort
    let l:items = []
    for l:i in a:x
        let l:items += lsp#ui#vim#utils#symbols_to_loc_list(l:i['server'], l:i)
    endfor
    call lsp#internal#ui#quickpick#items(l:items)
endfunction

function! s:on_accept(data, ...) abort
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
    call lsp#log('LspDocumentSymbolSearch error', a:e)
endfunction
