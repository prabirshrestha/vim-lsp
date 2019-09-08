" TODO: handle !has('signs')
" TODO: handle signs clearing when server exits
" https://github.com/vim/vim/pull/3652
let s:supports_signs = exists('*sign_define') && (has('nvim') || has('patch-8.1.0772'))
let s:enabled = 0
let s:signs = {} " { server_name: { path: {} } }
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

function! lsp#ui#vim#signs#enable() abort
    if !s:supports_signs
        call lsp#log('vim-lsp signs requires patch-8.1.0772')
        return
    endif
    if !s:enabled
        call s:define_signs()
        let s:enabled = 1
        call lsp#log('vim-lsp signs enabled')
    endif
endfunction

" Set default sign text to handle case when user provides empty dict
function! s:add_sign(sign_name, sign_default_text, sign_options) abort
    if !s:supports_signs | return | endif
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

function! s:define_signs() abort
    if !s:supports_signs | return | endif
    " let vim handle errors/duplicate instead of us maintaining the state
    call s:add_sign('LspError', 'E>', g:lsp_signs_error)
    call s:add_sign('LspWarning', 'W>', g:lsp_signs_warning)
    call s:add_sign('LspInformation', 'I>', g:lsp_signs_information)
    call s:add_sign('LspHint', 'H>', g:lsp_signs_hint)
endfunction

function! lsp#ui#vim#signs#disable() abort
    if s:enabled
        call s:clear_all_signs()
        call s:undefine_signs()
        let s:enabled = 0
        call lsp#log('vim-lsp signs disabled')
    endif
endfunction

function! s:clear_all_signs() abort
    if !s:supports_signs | return | endif
    for l:server_name in lsp#get_server_names()
        let l:sign_group = s:get_sign_group(l:server_name)
        call sign_unplace(l:sign_group)
    endfor
endfunction

function! s:undefine_signs() abort
    if !s:supports_signs | return | endif
    call sign_undefine('LspError')
    call sign_undefine('LspWarning')
    call sign_undefine('LspInformation')
    call sign_undefine('LspHint')
endfunction

function! lsp#ui#vim#signs#set(server_name, data) abort
    if !s:supports_signs | return | endif
    if !s:enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']

    let l:path = lsp#utils#uri_to_path(l:uri)

    " will always replace existing set
    call s:clear_signs(a:server_name, l:path)
    call s:place_signs(a:server_name, l:path, l:diagnostics)
endfunction

function! s:clear_signs(server_name, path) abort
    if !s:supports_signs || !bufloaded(a:path) | return | endif
    let l:sign_group = s:get_sign_group(a:server_name)
    call sign_unplace(l:sign_group, { 'buffer': a:path })
endfunction

function! s:get_sign_group(server_name) abort
    return 'vim_lsp_' . a:server_name
endfunction

function! s:place_signs(server_name, path, diagnostics) abort
    if !s:supports_signs | return | endif

    let l:sign_group = s:get_sign_group(a:server_name)

    if !empty(a:diagnostics) && bufnr(a:path) >= 0
        for l:item in a:diagnostics
            let l:line = l:item['range']['start']['line'] + 1

            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:sign_name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
                let l:sign_priority = get(g:lsp_signs_priority_map, l:sign_name, g:lsp_signs_priority)
                let l:sign_priority = get(g:lsp_signs_priority_map,
                                          \a:server_name . '_' . l:sign_name, l:sign_priority)
                " pass 0 and let vim generate sign id
                let l:sign_id = sign_place(0, l:sign_group, l:sign_name, a:path,
                                           \{ 'lnum': l:line, 'priority': l:sign_priority })
                call lsp#log('add signs', l:sign_id)
            endif
        endfor
    endif
endfunction
" vim sw=4 ts=4 et
