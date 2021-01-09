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

    let s:items = []
    call lsp#internal#ui#quickpick#open({
        \ 'items': [],
        \ 'busy': 1,
        \ 'input': '',
        \ 'key': 'text',
        \ 'on_accept': function('s:on_accept'),
        \ })

    call lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#callbag#pipe(
        \       lsp#request(server, {
        \           'method': 'textDocument/documentSymbol',
        \           'params': {
        \               'textDocument': lsp#get_text_document_identifier(l:bufnr),
        \           },
        \       }),
        \       lsp#callbag#map({x->{'server': server, 'response': x['response']}}),
        \   )
        \ }),
        \ lsp#callbag#flatMap({x->s:show_ui(x['server'], x['response'])}),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! s:show_ui(server, response) abort
    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:server, { 'response': a:response })
    let s:items += l:list
    call lsp#internal#ui#quickpick#items(s:items)
    call lsp#internal#ui#quickpick#busy(0)
    return lsp#callbag#empty()
endfunction

function! s:on_accept(data, ...) abort
    call lsp#internal#ui#quickpick#close()
    call lsp#utils#location#_open_vim_list_item(a:data['items'][0], '')
endfunction
