let s:enabled = 0
let s:already_setup = 0
let s:servers = {} " { server_name: { server_info } }

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

" @params
" server_info = {
"    'name': 'tsc',             required
"    'whitelist': [],           optional
"    'blacklist': [],           optional
" }
"
" @return
"   -1: Server already registered
"    1: Server registered successfully
"
" @example
" au User lsp_setup call lsp#register_server({
"   \ 'name': 'tsc',
"   \ })
function! lsp#register_server(server_info) abort
    call lsp#log('lsp-core', 'registering server', a:server_info['name'])
    if has_key(s:servers, a:server_info['name'])
        call lsp#log('lsp-core', 'server already registered', a:server_info['name'])
        return -1
    endif
    let s:servers[a:server_info['name']['server_info']] = a:server_info
    call lsp#log('lsp-core', 'registered server', a:server_info['name'])
    return 1
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
