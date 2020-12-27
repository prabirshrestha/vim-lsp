" Refer to https://github.com/microsoft/language-server-protocol/pull/1019 on normalization of urls.
" {
"   'normalized_uri': {
"       'server_name': {
"           'method': 'textDocument/publishDiagnostics',
"           'params': {
"               'uri': 'uri',        " this uri is not normalized and is exactly what server returns
"               'dignostics': [      " array can never be null but can be empty
"                   https://microsoft.github.io/language-server-protocol/specifications/specification-current/#diagnostic
"                   { range, message, severity?, code?, codeDesciption?, source?, tags?, relatedInformation?, data? }
"               ]
"           }
"       }
"   }
" Note: Do not remove when buffer unloads or doesn't exist since some server
" may send diagnsotics information regardless of textDocument/didOpen.
" buffer state is removed when server exists.
" TODO: reset buffer state when server initializes.
let s:diagnostics_state = {}
let s:enabled = 0

function! lsp#internal#diagnostics#state#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_enabled | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#pipe(
        \       lsp#stream(),
        \       lsp#callbag#filter({x->has_key(x, 'server') && has_key(x, 'response')
        \           && get(x['response'], 'method', '') ==# 'textDocument/publishDiagnostics'}),
        \       lsp#callbag#tap({x->s:on_text_documentation_publish_diagnostics(x['server'], x['response'])}),
        \   ),
        \   lsp#callbag#pipe(
        \       lsp#stream(),
        \       lsp#callbag#filter({x->has_key(x, 'server') && has_key(x, 'response')
        \           && get(x['response'], 'method', '') ==# '$/vimlsp/lsp_server_exit' }),
        \       lsp#callbag#tap({x->s:on_exit(x['response'])}),
        \   ),
        \ ),
        \ lsp#callbag#subscribe(),
        \ )

    " TODO: Notify diagnostics update
endfunction

function! lsp#internal#diagnostics#state#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    call lsp#internal#diagnostics#state#_reset()
    " TODO: Notify diagnostics update
    let s:enabled = 0
endfunction

function! lsp#internal#diagnostics#state#_reset() abort
    let s:diagnostics_state = {}
endfunction

" callers should always treat the return value as immutable
" @return {
"   'servername': response
" }
function! lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(uri) abort
    return get(s:diagnostics_state, lsp#utils#normalize_uri(a:uri), {})
endfunction

" callers should always treat the return value as immutable
" @return {
"   'normalized_uri': {
"       'servername': response
"   }
" }
function! lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_uri_and_server() abort
    return s:diagnostics_state
endfunction

function! s:on_text_documentation_publish_diagnostics(server, response) abort
    if lsp#client#is_error(a:response) | return | endif
    let l:normalized_uri = lsp#utils#normalize_uri(a:response['params']['uri'])
    if !has_key(s:diagnostics_state, l:normalized_uri)
        let s:diagnostics_state[l:normalized_uri] = {}
    endif
    let s:diagnostics_state[l:normalized_uri][a:server] = a:response
endfunction

function! s:on_exit(response) abort
    let l:server = a:response['params']['server']
    for [l:key, l:value] in items(s:diagnostics_state)
        if has_key(l:value, l:server)
            call remove(l:value, l:server)
        endif
    endfor
    " TODO: Notify diagnostics update
endfunction
