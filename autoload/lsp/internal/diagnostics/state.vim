" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#diagnostic
"
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
" buffer state is removed when server exits.
" TODO: reset buffer state when server initializes. ignoring for now for perf.
let s:diagnostics_state = {}

" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0

let s:diagnostic_kinds = {
    \ 1: 'error',
    \ 2: 'warning',
    \ 3: 'information',
    \ 4: 'hint',
    \ }

function! lsp#internal#diagnostics#state#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_enabled | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    call lsp#internal#diagnostics#state#_reset()

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

    call s:notify_diagnostics_update()
endfunction

function! lsp#internal#diagnostics#state#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    call lsp#internal#diagnostics#state#_reset()
    call s:notify_diagnostics_update()
    let s:enabled = 0
endfunction

function! lsp#internal#diagnostics#state#_reset() abort
    let s:diagnostics_state = {}
    let s:diagnostics_disabled_buffers = {}
endfunction

" callers should always treat the return value as immutable
" @return {
"   'servername': response
" }
function! lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(uri) abort
    return get(s:diagnostics_state, lsp#utils#normalize_uri(a:uri), {})
endfunction

" callers should always treat the return value as immutable.
" callers should treat uri as normalized via lsp#utils#normalize_uri
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
    call s:notify_diagnostics_update(a:server, l:normalized_uri)
endfunction

function! s:on_exit(response) abort
    let l:server = a:response['params']['server']
    let l:notify = 0
    for [l:key, l:value] in items(s:diagnostics_state)
        if has_key(l:value, l:server)
            let l:notify = 1
            call remove(l:value, l:server)
        endif
    endfor
    if l:notify | call s:notify_diagnostics_update(l:server) | endif
endfunction

function! lsp#internal#diagnostics#state#_force_notify_buffer(buffer) abort
    " TODO: optimize buffer only
    call s:notify_diagnostics_update()
endfunction

" call s:notify_diagnostics_update()
" call s:notify_diagnostics_update('server')
" call s:notify_diagnostics_update('server', 'uri')
function! s:notify_diagnostics_update(...) abort
    let l:data = { 'server': '$vimlsp', 'response': { 'method': '$/vimlsp/lsp_diagnostics_updated', 'params': {} } }
    " if a:0 > 0 | let l:data['response']['params']['server'] = a:1 | endif
    " if a:0 > 1 | let l:data['response']['params']['uri'] = a:2 | endif
    call lsp#stream(1, l:data)
    doautocmd <nomodeline> User lsp_diagnostics_updated
endfunction

function! lsp#internal#diagnostics#state#_enable_for_buffer(bufnr) abort
    if getbufvar(a:bufnr, 'lsp_diagnostics_enabled', 1) == 0
        call setbufvar(a:bufnr, 'lsp_diagnostics_enabled', 1)
        call s:notify_diagnostics_update()
    endif
endfunction

function! lsp#internal#diagnostics#state#_disable_for_buffer(bufnr) abort
    if getbufvar(a:bufnr, 'lsp_diagnostics_enabled', 1) != 0
        call setbufvar(a:bufnr, 'lsp_diagnostics_enabled', 0)
        call s:notify_diagnostics_update()
    endif
endfunction

function! lsp#internal#diagnostics#state#_is_enabled_for_buffer(bufnr) abort
    return getbufvar(a:bufnr, 'lsp_diagnostics_enabled', 1) == 1
endfunction

" Return dict with diagnostic counts for the specified buffer
" { 'error': 1, 'warning': 0, 'information': 0, 'hint': 0 }
function! lsp#internal#diagnostics#state#_get_diagnostics_count_for_buffer(bufnr) abort
    let l:counts = {
        \ 'error': 0,
        \ 'warning': 0,
        \ 'information': 0,
        \ 'hint': 0,
        \ }
    if lsp#internal#diagnostics#state#_is_enabled_for_buffer(a:bufnr)
        let l:uri = lsp#utils#get_buffer_uri(a:bufnr)
        for [l:_, l:response] in items(lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri))
            for l:diagnostic in lsp#utils#iteratable(l:response['params']['diagnostics'])
                let l:key = get(s:diagnostic_kinds, get(l:diagnostic, 'severity', 1) , 'error')
                let l:counts[l:key] += 1
            endfor
        endfor
    end
    return l:counts
endfunction
