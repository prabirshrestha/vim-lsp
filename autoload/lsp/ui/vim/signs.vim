" TODO: handle !has('signs')
" TODO: handle signs clearing when server exits
let s:enabled = 0
let s:signs_defined = 0
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
    if !s:enabled
        call s:define_signs()
        let s:enabled = 1
        call lsp#log('vim-lsp signs enabled')
    endif
endfunction

" Set default sign text to handle case when user provides empty dict
function! s:add_sign(sign_name, sign_default_text, sign_options) abort
    let l:sign_string = 'sign define ' . a:sign_name
    let l:sign_string .= ' text=' . get(a:sign_options, 'text', a:sign_default_text)
    let l:sign_icon = get(a:sign_options, 'icon', '')
    if !empty(l:sign_icon)
        let l:sign_string .= ' icon=' . l:sign_icon
    endif
    let l:sign_string .= ' texthl=' . a:sign_name . 'Text'
    let l:sign_string .= ' linehl=' . a:sign_name . 'Line'
    exec l:sign_string
endfunction

function! s:define_signs() abort
    if !s:signs_defined
        call s:add_sign('LspError', 'E>', g:lsp_signs_error)
        call s:add_sign('LspWarning', 'W>', g:lsp_signs_warning)
        call s:add_sign('LspInformation', 'I>', g:lsp_signs_information)
        call s:add_sign('LspHint', 'H>', g:lsp_signs_hint)
        let s:signs_defined = 1
    endif
endfunction

function! lsp#ui#vim#signs#disable() abort
    if s:enabled
        call s:undefine_signs()
        let s:enabled = 0
        call lsp#log('vim-lsp signs disabled')
    endif
endfunction

function! s:undefine_signs() abort
    if s:signs_defined
        sign undefine LspError
        sign undefine LspWarning
        sign undefine LspInformation
        sign undefine LspHint
        let s:signs_defined = 0
    endif
endfunction

function! lsp#ui#vim#signs#set(server_name, data) abort
    " will always replace existing set
    if !s:enabled
        return
    endif

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']

    let l:path = lsp#utils#uri_to_path(l:uri)
    if !has_key(s:signs, a:server_name)
        let s:signs[a:server_name] = {}
    endif

    if !has_key(s:signs[a:server_name], l:path)
        let s:signs[a:server_name][l:path] = []
    endif

    call s:clear_signs(a:server_name, l:path)
    call s:place_signs(a:server_name, l:path, l:diagnostics)
endfunction

function! s:clear_signs(server_name, path) abort
    " TODO clear
    if !has_key(s:signs[a:server_name], a:path)
        return
    endif

    for l:id in s:signs[a:server_name][a:path]
        execute ":sign unplace " . l:id . " file=" . a:path
    endfor

    let s:signs[a:server_name][a:path] = []
endfunction

function! s:place_signs(server_name, path, diagnostics) abort
    if !empty(a:diagnostics)
        for l:item in a:diagnostics
            let l:line = l:item['range']['start']['line'] + 1

            let l:name = 'LspError'
            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
                execute ":sign place " . g:lsp_next_sign_id . " name=" . l:name . " line=" . l:line . " file=" . a:path
                call add(s:signs[a:server_name][a:path], g:lsp_next_sign_id)
                call lsp#log('add signs')
                let g:lsp_next_sign_id += 1
            endif
        endfor
    endif
endfunction
