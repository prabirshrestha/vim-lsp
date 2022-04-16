" https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction

" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0

let s:sign_group = 'vim_lsp_document_code_action_signs'

if !hlexists('LspCodeActionText')
    highlight link LspCodeActionText Normal
endif

function! lsp#internal#document_code_action#signs#_enable() abort
    if !lsp#utils#_has_signs() | return | endif
    " don't even bother registering if the feature is disabled
    if !g:lsp_document_code_action_signs_enabled | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    call s:define_sign('LspCodeAction', 'A>', g:lsp_document_code_action_signs_hint)

    " Note:
    " - update CodeAction signs when CusorMoved or CursorHold
    " - clear signs when InsertEnter or BufLeave
    " - debounce code action requests
    " - automatically switch to latest code action request via switchMap()
    " - cancel code action request via takeUntil() when BufLeave
    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#fromEvent(['CursorMoved', 'CursorHold']),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent(['InsertEnter', 'BufLeave']),
        \       lsp#callbag#tap({_ -> s:clear_signs() }),
        \   )
        \ ),
        \ lsp#callbag#filter({_ -> g:lsp_document_code_action_signs_enabled }),
        \ lsp#callbag#debounceTime(g:lsp_document_code_action_signs_delay),
        \ lsp#callbag#map({_->{'bufnr': bufnr('%'), 'curpos': getcurpos()[0:2], 'changedtick': b:changedtick }}),
        \ lsp#callbag#distinctUntilChanged({a,b -> a['bufnr'] == b['bufnr'] && a['curpos'] == b['curpos'] && a['changedtick'] == b['changedtick']}),
        \ lsp#callbag#filter({_->mode() is# 'n' && getbufvar(bufnr('%'), '&buftype') !=# 'terminal' }),
        \ lsp#callbag#switchMap({_->
        \   lsp#callbag#pipe(
        \       s:send_request(),
        \       lsp#callbag#materialize(),
        \       lsp#callbag#filter({x->lsp#callbag#isNextNotification(x)}),
        \       lsp#callbag#map({x->x['value']}),
        \       lsp#callbag#takeUntil(
        \           lsp#callbag#fromEvent('BufLeave')
        \       )
        \   )
        \ }),
        \ lsp#callbag#subscribe({x->s:set_signs(x)}),
        \)
endfunction

function! lsp#internal#document_code_action#signs#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:send_request() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_code_action_provider(v:val)')

    if empty(l:servers)
        return lsp#callbag#empty()
    endif

    let l:range = lsp#utils#range#_get_current_line_range()
    return lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#request(server, {
        \       'method': 'textDocument/codeAction',
        \       'params': {
        \           'textDocument': lsp#get_text_document_identifier(),
        \           'range': l:range,
        \           'context': {
        \               'diagnostics': [],
        \               'only': ['', 'quickfix', 'refactor', 'refactor.extract', 'refactor.inline', 'refactor.rewrite'],
        \           }
        \       }
        \   })
        \ }),
        \ lsp#callbag#filter({x-> !lsp#client#is_error(x['response']) && !empty(x['response']['result'])}),
        \ lsp#callbag#take(1),
        \ )
endfunction

function! s:clear_signs() abort
    call sign_unplace(s:sign_group)
endfunction

function! s:set_signs(data) abort
    call s:clear_signs()

    if lsp#client#is_error(a:data['response']) | return | endif

    if empty(a:data['response']['result'])
        return
    endif

    let l:bufnr = bufnr(lsp#utils#uri_to_path(a:data['request']['params']['textDocument']['uri']))
    call s:place_signs(a:data, l:bufnr)
endfunction

" Set default sign text to handle case when user provides empty dict
function! s:define_sign(sign_name, sign_default_text, sign_options) abort
    let l:options = {
        \ 'text': get(a:sign_options, 'text', a:sign_default_text),
        \ 'texthl': a:sign_name . 'Text',
        \ 'linehl': a:sign_name . 'Line',
        \ }
    let l:sign_icon = get(a:sign_options, 'icon', '')
    if !empty(l:sign_icon)
        let l:options['icon'] = l:sign_icon
    endif
    call sign_define(a:sign_name, l:options)
endfunction

function! s:place_signs(data, bufnr) abort
    if !bufexists(a:bufnr) || !bufloaded(a:bufnr)
        return
    endif
    let l:sign_priority = g:lsp_document_code_action_signs_priority
    let l:line = lsp#utils#position#lsp_line_to_vim(a:bufnr, a:data['request']['params']['range']['start'])
    let l:sign_id = sign_place(0, s:sign_group, 'LspCodeAction', a:bufnr, 
        \ { 'lnum': l:line, 'priority': l:sign_priority })
endfunction
