" vint: -ProhibitUnusedVariable

"
" @param option = {
"   sync: v:true | v:false = Specify enable synchronous request.
" }
"
function! lsp#ui#vim#code_lens#do(option) abort
    let l:sync = get(a:option, 'sync', v:false)

    let s:items = []

    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_code_lens_provider(v:val)')
    if len(l:servers) == 0
        return lsp#utils#error('Code lens not supported for ' . &filetype)
    endif

    redraw | echo 'Retrieving codelens ...'

    let l:bufnr = bufnr('%')

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
        \       lsp#callbag#map({x->{ 'server': server, 'codelens': x }}),
        \   )
        \ }),
        \ lsp#callbag#takeUntil(lsp#callbag#pipe(
        \   lsp#stream(),
        \   lsp#callbag#filter({x->has_key(x, 'command')}),
        \ )),
        \ lsp#callbag#subscribe({
        \   'next':{x->add(s:items, x)},
        \   'complete': {->s:chooseCodeLens(s:items, l:bufnr)},
        \   'error': {e->s:error(x)},
        \ }),
        \ )
endfunction

function! s:resolve_if_required(server, response) abort
    let l:codelens = a:response['result']
    if empty(l:codelens)
        return lsp#callbag#empty()
    endif

    return lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:codelens),
        \ lsp#callbag#flatMap({codelens-> has_key(codelens, 'command') ? lsp#callbag#of(codelens) : s:resolve_codelens(a:server, codelens) }),
        \ )
endfunction

function! s:resolve_codelens(server, codelens) abort
    " TODO: return callbag#lsp#empty() if codelens resolve not supported by server
    return lsp#callbag#pipe(
        \ lsp#request(a:server, {
        \   'method': 'codeLens/resolve',
        \   'params': a:codelens
        \ }),
        \ lsp#callbag#map({x->x['response']['result']}),
        \ )
endfunction

function! s:chooseCodeLens(items, bufnr) abort
    redraw | echo 'Select codelens:'
    if empty(a:items)
        call lsp#utils#error('No codelens found')
        return
    endif
    let l:index = inputlist(map(copy(a:items), {i, value ->
        \   printf('%s - [%s] %s', i + 1, value['server'], value['codelens']['command']['title'])
        \ }))
    if l:index > 0 && l:index <= len(a:items)
        let l:selected = a:items[l:index - 1]
        call s:handle_code_lens_command(l:selected['server'], l:selected['codelens'], a:bufnr)
    endif
endfunction

function! s:error(e) abort
    call lsp#utils#error('Echo occured during CodeLens' . a:e)
endfunction

function! s:handle_code_lens_command(server, codelens, bufnr) abort
    call lsp#ui#vim#execute_command#_execute({
        \   'server_name': a:server,
        \   'command_name': get(a:codelens['command'], 'command', ''),
        \   'command_args': get(a:codelens['command'], 'arguments', v:null),
        \   'sync': 0,
        \   'bufnr': a:bufnr,
        \ })
endfunction
