" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0
let s:namespace_id = '' " will be set when enabled
let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !hlexists('LspErrorVirtualText')
  if !hlexists('LspErrorText')
    highlight link LspErrorVirtualText Error
  else
    highlight link LspErrorVirtualText LspErrorText
  endif
endif

if !hlexists('LspWarningVirtualText')
  if !hlexists('LspWarningText')
    highlight link LspWarningVirtualText Todo
  else
    highlight link LspWarningVirtualText LspWarningText
  endif
endif

if !hlexists('LspInformationVirtualText')
  if !hlexists('LspInformationText')
    highlight link LspInformationVirtualText Normal
  else
    highlight link LspInformationVirtualText LspInformationText
  endif
endif

if !hlexists('LspHintVirtualText')
  if !hlexists('LspHintText')
    highlight link LspHintVirtualText Normal
  else
    highlight link LspHintVirtualText LspHintText
  endif
endif

function! lsp#internal#diagnostics#virtual_text#_enable() abort
    " don't even bother registering if the feature is disabled
    if !lsp#utils#_has_virtual_text() | return | endif
    if !g:lsp_diagnostics_virtual_text_enabled | return | endif 

    if s:enabled | return | endif
    let s:enabled = 1

    if empty(s:namespace_id)
        let s:namespace_id = nvim_create_namespace('vim_lsp_diagnostic_virtual_text')
    endif

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
        \       lsp#callbag#filter({_->!g:lsp_diagnostics_virtual_text_insert_mode_enabled}),
        \       lsp#callbag#map({_->{ 'uri': lsp#utils#get_buffer_uri() }}),
        \   ),
        \ ),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_virtual_text_enabled}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_virtual_text_delay),
        \ lsp#callbag#tap({x->s:clear_virtual_text(x)}),
        \ lsp#callbag#tap({x->s:set_virtual_text(x)}),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! lsp#internal#diagnostics#virtual_text#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    call s:clear_all_virtual_text()
    let s:enabled = 0
endfunction

function! s:clear_all_virtual_text() abort
    for l:bufnr in nvim_list_bufs()
        if bufexists(l:bufnr) && bufloaded(l:bufnr)
            call nvim_buf_clear_namespace(l:bufnr, s:namespace_id, 0, -1)
        endif
    endfor
endfunction

" params => {
"   server: ''  " optional
"   uri: ''     " optional
" }
function! s:clear_virtual_text(params) abort
    " TODO: optimize by looking at params
    call s:clear_all_virtual_text()
endfunction

" params => {
"   server: ''  " optional
"   uri: ''     " optional
" }
function! s:set_virtual_text(params) abort
    " TODO: optimize by looking at params
    if !g:lsp_diagnostics_virtual_text_insert_mode_enabled
        if mode()[0] ==# 'i' | return | endif
    endif

    for l:bufnr in nvim_list_bufs()
        if lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr) && bufexists(l:bufnr) && bufloaded(l:bufnr)
            let l:uri = lsp#utils#get_buffer_uri(l:bufnr)
            for [l:server, l:diagnostics_response] in items(lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri))
                call s:place_virtual_text(l:server, l:diagnostics_response, l:bufnr)
            endfor
        endif
    endfor
endfunction

function! s:place_virtual_text(server, diagnostics_response, bufnr) abort
    for l:item in lsp#utils#iteratable(a:diagnostics_response['params']['diagnostics'])
        " need to do -1 for virtual text
        let l:line = lsp#utils#position#lsp_line_to_vim(a:bufnr, l:item['range']['start']) - 1
        let l:name = get(s:severity_sign_names_mapping, get(l:item, 'severity', 3), 'LspError')
        let l:hl_name = l:name . 'VirtualText'
        call nvim_buf_set_virtual_text(a:bufnr, s:namespace_id, l:line,
            \ [[g:lsp_diagnostics_virtual_text_prefix . l:item['message'], l:hl_name]], {})
    endfor
endfunction
