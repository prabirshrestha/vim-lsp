let s:enabled = 0
let s:already_setup = 0

" do nothing, place it here only to avoid the message
autocmd User lsp_setup silent

function! lsp#log_verbose(...) abort
    if g:lsp_log_verbose
        call call(function('lsp#log'), a:000)
    endif
endfunction

function! lsp#log(...) abort
    if !empty(g:lsp_log_file)
        call writefile([json_encode(a:000)], g:lsp_log_file, 'a')
    endif
endfunction

function! lsp#enable() abort
    if s:enabled
        return
    endif
    if !s:already_setup
        doautocmd User lsp_setup
        let s:already_setup = 1
    endif
    let s:enabled = 1
    call s:register_events()
endfunction

function! lsp#disable() abort
    if !s:enabled
        return
    endif
    call s:unregister_events()
    let s:enabled = 0
endfunction

function s:register_events() abort
    augroup lsp
        autocmd!
        autocmd BufReadPost * call s:on_text_document_did_open()
        autocmd BufWritePost * call s:on_text_document_did_save()
        autocmd BufWinLeave * call s:on_text_document_did_close()
    augroup END
    call s:on_text_document_did_open()
endfunction

function! s:unregister_events() abort
    augroup lsp
        autocmd!
    augroup END
endfunction

function! s:on_text_document_did_open() abort
    call lsp#log('s:on_text_document_did_open()', bufnr('%'))
endfunction

function! s:on_text_document_did_save() abort
    call lsp#log('s:on_text_document_did_save()', bufnr('%'))
endfunction

function! s:on_text_document_did_close() abort
    call lsp#log('s:on_text_document_did_close()', bufnr('%'))
endfunction
