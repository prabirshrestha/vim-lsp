let s:enabled = 0

function! lsp#log(...) abort
    if !empty(g:lsp_log_file)
        call writefile([json_encode(a:000)], g:lsp_log_file, 'a')
    endif
endfunction

function! lsp#enable() abort
    if s:enabled
        return
    endif
    let s:enabled = 1
    call lsp#log('lsp-core', 'enabling')
    call s:register_events()
    call lsp#log('lsp-core', 'enabled')
endfunction

function! lsp#disable() abort
    if !s:enabled
        return
    endif
    let s:enabled = 0
    call lsp#log('lsp-core', 'disabled')
endfunction

function! s:register_events() abort
    call lsp#log('lsp-core', 'registering events')
    augroup lsp
        autocmd! * <buffer>
        autocmd BufReadPost * call s:on_text_document_did_open()
    augroup END
    call s:on_text_document_did_open()
    call lsp#log('lsp-core', 'registered events')
endfunction

function! s:on_text_document_did_open() abort
    call lsp#log('lsp-core', 's:on_text_document_did_open()')
endfunction
