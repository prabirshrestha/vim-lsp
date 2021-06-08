" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0
let s:sign_group = 'vim_lsp'

let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !hlexists('LspErrorText')
    highlight link LspErrorText Error
endif

if !hlexists('LspWarningText')
    highlight link LspWarningText Todo
endif

if !hlexists('LspInformationText')
    highlight link LspInformationText Normal
endif

if !hlexists('LspHintText')
    highlight link LspHintText Normal
endif

function! lsp#internal#diagnostics#signs#_enable() abort
    " don't even bother registering if the feature is disabled
    if !lsp#utils#_has_signs() | return | endif
    if !g:lsp_diagnostics_signs_enabled | return | endif 

    if s:enabled | return | endif
    let s:enabled = 1

    call s:define_sign('LspError', 'E>', g:lsp_diagnostics_signs_error)
    call s:define_sign('LspWarning', 'W>', g:lsp_diagnostics_signs_warning)
    call s:define_sign('LspInformation', 'I>', g:lsp_diagnostics_signs_information)
    call s:define_sign('LspHint', 'H>', g:lsp_diagnostics_signs_hint)

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#pipe(
        \       lsp#stream(),
        \       lsp#callbag#filter({x->has_key(x, 'server') && has_key(x, 'response')
        \       && has_key(x['response'], 'method') && x['response']['method'] ==# '$/vimlsp/lsp_diagnostics_updated'
        \       && !lsp#client#is_error(x['response'])}),
        \       lsp#callbag#map({x->x['response']['params']}),
        \   ),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent(['InsertEnter', 'InsertLeave']),
        \       lsp#callbag#filter({_->!g:lsp_diagnostics_signs_insert_mode_enabled}),
        \       lsp#callbag#map({_->{ 'uri': lsp#utils#get_buffer_uri() }}),
        \   ),
        \ ),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_signs_enabled}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_signs_delay),
        \ lsp#callbag#tap({x->s:clear_signs(x)}),
        \ lsp#callbag#tap({x->s:set_signs(x)}),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! lsp#internal#diagnostics#signs#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    call s:clear_all_signs()
    call s:undefine_signs()
    let s:enabled = 0
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

function! s:undefine_signs() abort
    call sign_undefine('LspError')
    call sign_undefine('LspWarning')
    call sign_undefine('LspInformation')
    call sign_undefine('LspHint')
endfunction

function! s:clear_all_signs() abort
    call sign_unplace(s:sign_group)
endfunction

" params => {
"   server: ''  " optional
"   uri: ''     " optional
" }
function! s:clear_signs(params) abort
    " TODO: optimize by looking at params
    call s:clear_all_signs()
endfunction

" params => {
"   server: ''  " optional
"   uri: ''     " optional
" }
function! s:set_signs(params) abort
    " TODO: optimize by looking at params
    if !g:lsp_diagnostics_signs_insert_mode_enabled
        if mode()[0] ==# 'i' | return | endif
    endif

    for l:bufnr in range(1, bufnr('$'))
        if lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr) && bufexists(l:bufnr) && bufloaded(l:bufnr)
            let l:uri = lsp#utils#get_buffer_uri(l:bufnr)
            for [l:server, l:diagnostics_response] in items(lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri))
                call s:place_signs(l:server, l:diagnostics_response, l:bufnr)
            endfor
        endif
    endfor
endfunction

function! s:place_signs(server, diagnostics_response, bufnr) abort
    for l:item in lsp#utils#iteratable(a:diagnostics_response['params']['diagnostics'])
        let l:line = lsp#utils#position#lsp_line_to_vim(a:bufnr, l:item['range']['start'])
        if has_key(l:item, 'severity') && !empty(l:item['severity'])
            let l:sign_name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
            let l:sign_priority = get(g:lsp_diagnostics_signs_priority_map, l:sign_name, g:lsp_diagnostics_signs_priority)
            let l:sign_priority = get(g:lsp_diagnostics_signs_priority_map,
                \ a:server . '_' . l:sign_name, l:sign_priority)
            " pass 0 and let vim generate sign id
            let l:sign_id = sign_place(0, s:sign_group, l:sign_name, a:bufnr,
                \{ 'lnum': l:line, 'priority': l:sign_priority })
        endif
    endfor
endfunction
