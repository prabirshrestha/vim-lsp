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
let s:diagnostics_state = {}

function! lsp#internal#diagnostics#state#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_enabled | return | endif

    call lsp#internal#diagnostics#state#_disable()

    " TODO:
    " * remove when buffer unloads
    " * remove when server exits

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#stream(),
        \ lsp#callbag#filter({x->has_key(x, 'server') && has_key(x, 'response')
        \   && get(x['response'], 'method', '') ==# 'textDocument/publishDiagnostics'}),
        \ lsp#callbag#subscribe({
        \   'next':{x->lsp#internal#diagnostics#state#_on_text_document_publish_diagnostics(x['server'], x['response'])}
        \ }),
        \ )
endfunction

function! lsp#internal#diagnostics#state#_disable() abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
        call lsp#internal#diagnostics#state#_reset()
        " TODO: Notify diagnostics update
    endif
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

function! lsp#internal#diagnostics#state#_on_text_document_publish_diagnostics(server, response) abort
    if lsp#client#is_error(a:response) | return | endif
    let l:normalized_uri = lsp#utils#normalize_uri(a:response['params']['uri'])
    if !has_key(s:diagnostics_state, l:normalized_uri)
        let s:diagnostics_state[l:normalized_uri] = {}
    endif
    let s:diagnostics_state[l:normalized_uri][a:server] = a:response
endfunction

