let s:enabled = 0
let s:already_setup = 0
let s:servers = {} " { lsp_id, server_info, initialize_response?, buffers: { path: { dirty } }

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
    for l:server_name in a:server_names
        if s:ensure_start(l:server_name) > 0
            if s:ensure_init(l:server_name) > 0
                let l:server = s:servers[l:server_name]
                let l:buffers = l:server['buffers']
                let l:buffer_uri = s:get_buffer_uri()
                if !has_key(l:buffers, a:buf)
                    " buffer isn't open, so open it
                    let l:buffers[l:buffer_uri] = { 'dirty': 0, 'version': 1 }
                    call s:send_request(l:server_name, {
                        \ 'method': 'textDocument/didOpen',
                        \ 'params': {
                        \   'textDocument': s:get_text_document(l:buffers[l:buffer_uri]),
                        \ },
                        \ })
                elseif l:buffers[l:buffer_uri]['dirty']
                    " send didChange event
                endif
            endif
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
            \ 'on_notification': function('s:on_notification', [a:server_name]),
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

function! s:ensure_init(server_name) abort
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    if has_key(l:server, 'initialize_response')
        " it is either initializing or already initialized
        return 1
    endif

    if has_key(l:server_info, 'root_uri')
        let l:root_uri = l:server_info['root_uri'](l:server_info)
    else
        let l:root_uri = s:get_default_root_uri()
    endif

    if empty(l:root_uri)
        call lsp#log('s:ensure_init', 'root_uri empty', 'ignoring initialization', a:server_name)
        return -1
    endif

    " set to empty so we know that it initialize request is in flight
    let l:server['initialize_response'] = {}

    call s:send_request(a:server_name, {
        \ 'method': 'initialize',
        \ 'params': {
        \   'capabilities': {},
        \   'root_uri': l:root_uri,
        \   'root_path': l:root_uri,
        \ }
        \ })

    return 1
endfunction

function! s:send_request(server_name, data) abort
    let l:lsp_id = s:servers[a:server_name]['lsp_id']
    call lsp#log_verbose('--->', l:lsp_id, a:server_name, a:data)
    call lsp#client#send_request(l:lsp_id, a:data)
endfunction

function! s:on_stderr(server_name, id, data, event) abort
    call lsp#log_verbose('<---(stderr)', a:id, a:server_name, a:data)
endfunction

function! s:on_exit(server_name, id, data, event) abort
    call lsp#log('s:on_exit', a:id, a:server_name, 'exited', a:data)
    if has_key(s:servers, a:server_name)
        let l:server = s:servers[a:server_name]
        let l:server['lsp_id'] = 0
        let l:server['buffers'] = {}
        if has_key(l:server, 'initialize_response')
            unlet l:server['initialize_response']
        endif
    endif
endfunction

function! s:on_notification(server_name, id, data, event) abort
    call lsp#log_verbose('<---', a:id, a:server_name, a:data)
    let l:respone = a:data['response']
    let l:server = s:servers[a:server_name]

    if lsp#client#is_error(l:response)
        " todo
    elseif lsp#client#is_server_instantiated_notification(l:response)
        " todo
    else
        let l:request = a:data['request']
        let l:method = a:request['method']
        if l:method == 'initalize'
            let l:server['initialize_response'] = l:response
        endif
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

function! s:get_default_root_uri() abort
    return s:path_to_uri(getcwd())
endfunction

function! s:get_buffer_uri() abort
    return s:path_to_uri(expand('%:p'))
endfunction

if has('win32') || has('win64')
    function! s:path_to_uri(path) abort
        return 'file:///' . substitute(a:path, '\', '/', 'g')
    endfunction
else
    function! s:path_to_uri(path) abort
        return 'file://' . a:path
    endfunction
endif

function! s:get_text_document(buffer_info) abort
    return {
        \ 'uri': s:get_buffer_uri(),
        \ 'languageId': &filetype,
        \ 'version': a:buffer_info['version'],
        \ 'text': join(getline(1, '$'), "\n"),
        \ }
endfunction
