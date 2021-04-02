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
    return lsp#callbag#create(function('s:quickpick_open', [a:items, a:bufnr]))
endfunction

function! lsp#ui#vim#code_lens#_get_subtitle(item) abort
    " Since element of arguments property of Command interface is defined as any in LSP spec, it is
    " up to the language server implementation.
    " Currently this only impacts rust-analyzer. See #1118 for more details.

    if !has_key(a:item['codelens']['command'], 'arguments')
        return ''
    endif

    let l:arguments = a:item['codelens']['command']['arguments']
    for l:argument in l:arguments
        if type(l:argument) != type({}) || !has_key(l:argument, 'label')
            return ''
        endif
    endfor

    return ': ' . join(map(copy(l:arguments), 'v:val["label"]'), ' > ')
endfunction

function! s:quickpick_open(items, bufnr, next, error, complete) abort
    if empty(a:items)
        return lsp#callbag#empty()
    endif

    let l:items = []
    for l:item in a:items
        let l:title = printf("[%s] %s%s\t| L%s:%s",
            \ l:item['server'],
            \ l:item['codelens']['command']['title'],
            \ lsp#ui#vim#code_lens#_get_subtitle(l:item),
            \ lsp#utils#position#lsp_line_to_vim(a:bufnr, l:item['codelens']['range']['start']),
            \ getbufline(a:bufnr, lsp#utils#position#lsp_line_to_vim(a:bufnr, l:item['codelens']['range']['start']))[0])
        call add(l:items, { 'title': l:title, 'item': l:item })
    endfor

    call lsp#internal#ui#quickpick#open({
        \ 'items': l:items,
        \ 'key': 'title',
        \ 'on_accept': function('s:quickpick_accept', [a:next, a:error, a:complete]),
        \ 'on_cancel': function('s:quickpick_cancel', [a:next, a:error, a:complete]),
        \ })

    return function('s:quickpick_dispose')
endfunction

function! s:quickpick_dispose() abort
    call lsp#internal#ui#quickpick#close()
endfunction

function! s:quickpick_accept(next, error, complete, data, ...) abort
    call lsp#internal#ui#quickpick#close()
    let l:items = a:data['items']
    if len(l:items) > 0
        call a:next(l:items[0]['item'])
    endif
    call a:complete()
endfunction

function! s:quickpick_cancel(next, error, complete, ...) abort
    call a:complete()
endfunction
