let s:supports_vt = exists('*nvim_buf_set_virtual_text')
let s:enabled = 0
let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !hlexists('LspErrorVirtual')
  if !hlexists('LspErrorText')
    highlight link LspErrorVirtual Error
  else
    highlight link LspErrorVirtual LspErrorText
  endif
endif

if !hlexists('LspWarningVirtual')
  if !hlexists('LspWarningText')
    highlight link LspWarningVirtual Todo
  else
    highlight link LspWarningVirtual LspWarningText
  endif
endif

if !hlexists('LspInformationVirtual')
  if !hlexists('LspInformationText')
    highlight link LspInformationVirtual Normal
  else
    highlight link LspInformationVirtual LspInformationText
  endif
endif

if !hlexists('LspHintVirtual')
  if !hlexists('LspHintText')
    highlight link LspHintVirtual Normal
  else
    highlight link LspHintVirtual LspHintText
  endif
endif

function! lsp#ui#vim#virtual#enable() abort
    if !s:supports_vt
        call lsp#log('vim-lsp virtual text requires neovim')
        return
    endif
    if !s:enabled
        let s:enabled = 1
        call lsp#log('vim-lsp virtual text enabled')
    endif
endfunction

function! lsp#ui#vim#virtual#disable() abort
    if s:enabled
        for l:ns in keys(nvim_get_namespaces())
            call s:clear_all_virtual(l:ns)
        endfor

        let s:enabled = 0
        call lsp#log('vim-lsp virtual text disabled')
    endif
endfunction

function! s:get_virtual_group(name) abort
    return nvim_create_namespace('vim_lsp_'.a:name)
endfunction

function! s:clear_all_virtual(ns) abort
    if a:ns =~# '^vim_lsp_'
        let l:ns = s:get_virtual_group(a:ns)
        for l:bufnr in nvim_list_bufs()
            call nvim_buf_clear_namespace(l:bufnr, l:ns, 0, -1)
        endfor
    endif
endfunction

function! s:clear_virtual(server_name, path) abort
    if !s:supports_vt | return | endif
    if !s:enabled | return | endif

    let l:ns = s:get_virtual_group(a:server_name)
    let l:bufnr = bufnr(a:path)

    if bufnr(a:path) >= 0
        call nvim_buf_clear_namespace(l:bufnr, l:ns, 0, -1)
    endif
endfunction

function! s:place_virtual(server_name, path, diagnostics) abort
    if !s:supports_vt | return | endif
    if !s:enabled | return | endif

    let l:ns = s:get_virtual_group(a:server_name)
    let l:bufnr = bufnr(a:path)

    if !empty(a:diagnostics) && bufnr(a:path) >= 0
        for l:item in a:diagnostics
            let l:line = l:item['range']['start']['line']

            let l:name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
            let l:hl_name = l:name . 'Virtual'
            call nvim_buf_set_virtual_text(l:bufnr, l:ns, l:line,
                        \ [[g:lsp_virtual_text_prefix . l:item['message'], l:hl_name]], {})
        endfor
    endif
endfunction

function! lsp#ui#vim#virtual#set(server_name, data) abort
    if !s:supports_vt | return | endif
    if !s:enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']

    let l:path = lsp#utils#uri_to_path(l:uri)

    " will always replace existing set
    call s:clear_virtual(a:server_name, l:path)
    call s:place_virtual(a:server_name, l:path, l:diagnostics)
endfunction
