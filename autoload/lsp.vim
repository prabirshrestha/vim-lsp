let s:enabled = 0
let s:already_setup = 0

" do nothing, place it here only to avoid the message
autocmd User lsp_setup silent

function! lsp#log(...) abort
    if !empty(g:lsp_log_file)
        call writefile([json_encode(a:000)], g:lsp_log_file, 'a')
    endif
endfunction

function! lsp#enable() abort
    if s:enabled
        return
    endif
    call lsp#log('lsp-core', 'enabling')
    if !s:already_setup
        call lsp#log('lsp-core', 'lsp_setup')
        doautocmd User lsp_setup
        let s:already_setup = 1
    endif
    let s:enabled = 1
    call s:register_events()
    call lsp#log('lsp-core', 'enabled')
endfunction

function! lsp#disable() abort
    if !s:enabled
        return
    endif
    call s:unregister_events()
    let s:enabled = 0
    call lsp#log('lsp-core', 'disabled')
endfunction

function! s:register_events() abort
    call lsp#log('lsp-core', 'registering events')
    augroup lsp
        autocmd!
        autocmd BufReadPost * call s:on_text_document_did_open()
        autocmd BufWritePost * call s:on_text_document_did_save()
        autocmd TextChangedI * call s:on_text_document_did_change()
    augroup END
    call lsp#log('lsp-core', 'registered events')
    call lsp#log('lsp-core', 'calling s:on_text_document_did_open() from s:register_events()')
    call s:on_text_document_did_open()
endfunction

function! s:unregister_events() abort
    call lsp#log('lsp-core', 'unregistering events')
    augroup lsp
        autocmd!
    augroup END
    call lsp#log('lsp-core', 'unregistered events')
endfunction

function! s:on_text_document_did_open() abort
    call lsp#log('lsp-core', 's:on_text_document_did_open()')
endfunction

function! s:on_text_document_did_save() abort
    call lsp#log('lsp-core', 's:on_text_document_did_save()')
endfunction

function! s:on_text_document_did_change() abort
    call lsp#log('lsp-core', 's:on_text_document_did_change()')
endfunction
