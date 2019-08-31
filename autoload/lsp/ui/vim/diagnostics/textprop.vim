let s:supports_hl = exists('*prop_add')
let s:enabled = 0
let s:prop_type_prefix = 'vim_lsp_hl_'

let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !hlexists('LspErrorHighlight')
    highlight link LspErrorHighlight Error
endif

if !hlexists('LspWarningHighlight')
    highlight link LspWarningHighlight Todo
endif

if !hlexists('LspInformationHighlight')
    highlight link LspInformationHighlight Normal
endif

if !hlexists('LspHintHighlight')
    highlight link LspHintHighlight Normal
endif

function! lsp#ui#vim#diagnostics#textprop#enable() abort
    if !s:supports_hl
        call lsp#log('vim-lsp highlighting requires vim with +textprop')
        return
    endif
    if !s:enabled
        let s:enabled = 1
        call lsp#log('vim-lsp highlighting enabled (textprop)')
    endif
endfunction

function! lsp#ui#vim#diagnostics#textprop#disable() abort
    if s:enabled
        call s:clear_all_highlights()
        let s:enabled = 0
        call lsp#log('vim-lsp highlighting disabled')
    endif
endfunction

function! lsp#ui#vim#diagnostics#textprop#set(server_name, data) abort
    if !s:enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']
    let l:path = lsp#utils#uri_to_path(l:uri)

    call s:clear_highlights(a:server_name, l:path)
    call s:place_highlights(a:server_name, l:path, l:diagnostics)
endfunction

function! s:get_prop_type(server_name, severity) abort
    let l:severity = has_key(s:severity_sign_names_mapping, a:severity) ? a:severity : 0
    let l:name = s:prop_type_prefix . l:severity . '_' . a:server_name
    if empty(prop_type_get(l:name))
        call prop_type_add(l:name, {
            \ 'highlight': s:severity_sign_names_mapping[l:severity] . 'Highlight',
            \ 'combine': v:true,
            \ })
    endif
    return l:name
endfunction

function! s:clear_all_highlights() abort
    for l:prop_type in prop_type_list()
        if l:prop_type !~# '^' . s:prop_type_prefix
            continue
        endif

        for l:bufnr in range(1, bufnr('$'))
            if bufexists(l:bufnr)
                call prop_remove({
                    \ 'type': l:prop_type,
                    \ 'bufnr': l:bufnr,
                    \ 'all': v:true,
                    \ })
            endif
        endfor

        call prop_type_delete(l:prop_type)
    endfor
endfunction

function! s:clear_highlights(server_name, path) abort
    if !s:enabled | return | endif

    let l:bufnr = bufnr(a:path)

    if l:bufnr == -1
        call lsp#log('Skipping clear_highlights for ' . a:path . ': buffer is not loaded')
        return
    endif

    for l:severity in keys(s:severity_sign_names_mapping)
        let l:prop_type = s:get_prop_type(a:server_name, l:severity)
        call prop_remove({
            \ 'type': l:prop_type,
            \ 'bufnr': l:bufnr,
            \ 'all': v:true,
            \ })
    endfor
endfunction

function! s:place_highlights(server_name, path, diagnostics) abort
    if !s:enabled | return | endif

    let l:bufnr = bufnr(a:path)
    if !empty(a:diagnostics) && l:bufnr >= 0
        for l:item in a:diagnostics
            let l:start_line = l:item['range']['start']['line'] + 1
            let l:start_char = l:item['range']['start']['character']
            let l:start_col = lsp#utils#to_col(l:bufnr, l:start_line, l:start_char)
            let l:end_line = l:item['range']['end']['line'] + 1
            let l:end_char = l:item['range']['end']['character']
            let l:end_col = lsp#utils#to_col(l:bufnr, l:end_line, l:end_char)

            let l:prop_type = s:get_prop_type(a:server_name, l:item['severity'])
            call prop_add(l:start_line, l:start_col, {
                \ 'end_lnum': l:end_line,
                \ 'end_col': l:end_col,
                \ 'bufnr': l:bufnr,
                \ 'type': l:prop_type,
                \ })
        endfor
    endif
endfunction
