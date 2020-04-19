let s:supports_hl = exists('*nvim_buf_add_highlight')
let s:enabled = 0
let s:ns_key = 'vim_lsp_hl_'

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

function! lsp#ui#vim#highlights#enable() abort
    if !s:supports_hl
        call lsp#log('vim-lsp highlighting requires neovim')
        return
    endif
    if !s:enabled
        let s:enabled = 1
        call lsp#log('vim-lsp highlighting enabled')
    endif
endfunction

function! lsp#ui#vim#highlights#disable() abort
    if s:enabled
        for l:ns in keys(nvim_get_namespaces())
            call s:clear_all_highlights(l:ns)
        endfor

        let s:enabled = 0
        call lsp#log('vim-lsp highlighting disabled')
    endif
endfunction

function! lsp#ui#vim#highlights#set(server_name, data) abort
    if !s:supports_hl | return | endif
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

function! s:get_highlight_group(name) abort
    return nvim_create_namespace(s:ns_key . a:name)
endfunction

function! s:clear_all_highlights(namespace) abort
    if a:namespace =~# '^' . s:ns_key
        let l:ns = nvim_create_namespace(a:namespace)
        for l:bufnr in nvim_list_bufs()
            call nvim_buf_clear_namespace(l:bufnr, l:ns, 0, -1)
        endfor
    endif
endfunction

function! s:clear_highlights(server_name, path) abort
    if !s:supports_hl | return | endif
    if !s:enabled | return | endif

    let l:ns = s:get_highlight_group(a:server_name)
    let l:bufnr = bufnr(a:path)

    if l:bufnr != -1
        call nvim_buf_clear_namespace(l:bufnr, l:ns, 0, -1)
    endif
endfunction

function! s:place_highlights(server_name, path, diagnostics) abort
    if !s:supports_hl | return | endif
    if !s:enabled | return | endif

    let l:ns = s:get_highlight_group(a:server_name)
    let l:bufnr = bufnr(a:path)

    if !empty(a:diagnostics) && l:bufnr >= 0
        for l:item in a:diagnostics
            let [l:line, l:start_col] = lsp#utils#position#lsp_to_vim(l:bufnr, l:item['range']['start'])
            let [l:_, l:end_col] = lsp#utils#position#lsp_to_vim(l:bufnr, l:item['range']['end'])

            let l:name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
            let l:hl_name = l:name . 'Highlight'
            call nvim_buf_add_highlight(l:bufnr, l:ns, l:hl_name, l:line - 1, l:start_col - 1, l:end_col - 1)
        endfor
    endif
endfunction
