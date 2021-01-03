" https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens

" @param option = {
" }
"
function! lsp#ui#vim#code_lens#do(option) abort
    let l:sync = get(a:option, 'sync', v:false)

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
        \               'textDocument': lsp#get_text_document_identifier(l:bufnr),
        \           },
        \       }),
        \       lsp#callbag#map({x->x['response']['result']}),
        \       lsp#callbag#filter({codelenses->!empty(codelenses)}),
        \       lsp#callbag#flatMap({codelenses->
        \           lsp#callbag#pipe(
        \               lsp#callbag#fromList(codelenses),
        \               lsp#callbag#flatMap({codelens->
        \                   has_key(codelens, 'command') ? lsp#callbag#of(codelens) : s:resolve_codelens(server, codelens)}),
        \           )
        \       }),
        \       lsp#callbag#map({codelens->{ 'server': server, 'codelens': codelens }}),
        \   )
        \ }),
        \ lsp#callbag#reduce({acc,curr->add(acc, curr)}, []),
        \ lsp#callbag#flatMap({x->s:chooseCodeLens(x, l:bufnr)}),
        \ lsp#callbag#tap({x-> lsp#ui#vim#execute_command#_execute({
        \   'server_name': x['server'],
        \   'command_name': get(x['codelens']['command'], 'command', ''),
        \   'command_args': get(x['codelens']['command'], 'arguments', v:null),
        \   'bufnr': l:bufnr,
        \ })}),
        \ lsp#callbag#takeUntil(lsp#callbag#pipe(
        \   lsp#stream(),
        \   lsp#callbag#filter({x->has_key(x, 'command')}),
        \ )),
        \ lsp#callbag#subscribe({
        \   'error': {e->lsp#utils#error('Error running codelens ' . json_encode(e))},
        \ }),
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
        return lsp#callbag#throwError('No codelens found')
    endif
    let l:index = inputlist(map(copy(a:items), {i, value ->
        \   printf('%s - [%s] %s', i + 1, value['server'], value['codelens']['command']['title'])
        \ }))
    if l:index > 0 && l:index <= len(a:items)
        let l:selected = a:items[l:index - 1]
        return lsp#callbag#of(l:selected)
    else
        return lsp#callbag#empty()
    endif
endfunction
