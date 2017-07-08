let s:enabled = 0
let s:already_setup = 0
let s:servers = {} " { lsp_id, server_info, buffers: { 1: { dirty } }

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

" @params {server_info} = {
"   'name': 'go-langserver',        " requried, must be unique
"   'whitelist': ['go'],            " optional, array of filetypes to whitelist, * for all filetypes
"   'blacklist': [],                " optional, array of filetypes to blacklist, * for all filetypes,
"   'cmd': {server_info->['go-langserver]} " function that takes server_info and returns array of cmd and args, return empty if you don't want to start the server
" }
function! lsp#register_server(server_info) abort
    let l:server_name = a:server_info['name']
    if has_key(s:servers, l:server_name)
        call lsp#log('lsp#register_server', 'server already registered', l:server_name)
    endif
    let s:servers[l:server_name] = {
        \ 'server_info': a:server_info,
        \ 'lsp_id': 0,
        \ 'buffers': {},
        \ }
    call lsp#log('lsp#register_server', 'server registered', l:server_name)
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
    call s:ensure_flush(bufnr('%'), s:get_active_servers_for_buffer())
endfunction

function! s:on_text_document_did_save() abort
    call lsp#log('s:on_text_document_did_save()', bufnr('%'))
endfunction

function! s:on_text_document_did_close() abort
    call lsp#log('s:on_text_document_did_close()', bufnr('%'))
endfunction

function! s:ensure_flush(buf, server_names) abort
    call lsp#log('s:ensure_flush', &ft, a:buf, a:server_names)
    for l:server_name in a:server_names
        if s:ensure_start(l:server_name) > 0
            " ensure init
        endif
    endfor
endfunction

function! s:ensure_start(server_name) abort
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    if l:server['lsp_id'] <= 0
        " try starting server since it hasn't started
        let l:cmd = l:server_info['cmd'](l:server_info)

        if empty(l:cmd)
            call lsp#log('s:ensure_flush()', 'ignore server start since cmd is empty', a:server_name)
            return -1
        endif

        let l:lsp_id = lsp#client#start({
            \ 'cmd': l:cmd,
            \ 'on_stderr': function('s:on_stderr', [a:server_name]),
            \ 'on_exit': function('s:on_exit', [a:server_name]),
            \ })

        if l:lsp_id > 0
            let l:server['lsp_id'] = l:lsp_id
            call lsp#log('s:ensure_flush()', 'server started', a:server_name, l:lsp_id, l:cmd)
            return l:server['lsp_id']
        else
            call lsp#log('s:ensure_flush()', 'server failed to start', a:server_name, l:lsp_id, l:cmd)
            return -1
        endif
    else
        call lsp#log('s:ensure_flush()', 'server already started', a:server_name)
        return l:server['lsp_id']
    endif
endfunction

function! s:on_stderr(server_name, id, data, event) abort
    call lsp#log_verbose('s:on_stderr <---', a:server_name, a:id, a:data)
endfunction

function! s:on_exit(server_name, id, data, event) abort
    call lsp#log('s:on_exit', a:server_name, 'exited', a:id, a:data)
    if has_key(s:server, a:server_name)
        let l:server = s:servers[a:server_name]
        let l:server['lsp_id'] = 0
        let l:server['buffers'] = {}
    endif
endfunction

function! s:get_active_servers_for_buffer() abort
    " TODO: cache active servers per buffer
    let l:active_servers = []

    for l:server_name in keys(s:servers)
        let l:server_info = s:servers[l:server_name]['server_info']
        let l:blacklisted = 0

        if has_key(l:server_info, 'blacklist')
            for l:filetype in l:server_info['blacklist']
                if l:filetype == &filetype || l:filetype == '*'
                    let l:blacklisted = 1
                    break
                endif
            endfor
        endif

        if l:blacklisted
            continue
        endif

        if has_key(l:server_info, 'whitelist')
            for l:filetype in l:server_info['whitelist']
                if l:filetype == &filetype || l:filetype == '*'
                    let l:active_servers += [l:server_name]
                    break
                endif
            endfor
        endif
    endfor

    return l:active_servers
endfunction

