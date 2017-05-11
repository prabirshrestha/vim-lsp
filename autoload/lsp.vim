let s:enabled = 0
let s:already_setup = 0
let s:servers = {} " { server_name: { lsp_id, server_info, protocol_version: { major }, init_response }
let s:lsp_id_mappings = {} " { lsp_id: server_name }

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
"    'name': 'tsc',                         required
"    'protocol_version': '3.0',             required
"    'cmd': [] or {server_info->[]}         optional, refer to lsp#start_server options
"    'root_uri: '' or {server_info->'' }    optiona, refer to lsp#start_server options
"    'whitelist': [],                       optional
"    'blacklist': [],                       optional
" }
" even though cmd and root_uri are optional it is highly recommened to set it here
"
" @return
"    1: Server registered successfully
"   -1: Server already registered
"   -2: Protocol version not specified
"   -3: Failed to parse protocol version
"   -4: Unsupported protocol version
"
" @example
" au User lsp_setup call lsp#register_server({
"   \ 'name': 'tsc',
"   \ 'protocol_version': '3.0',
"   \ 'cmd': has('win32') || has('win64') ? ['cmd', '/c', 'javascript-typescript-stdio'] : ['sh', '-c', 'javascript-typescript-stdio']
"   \ })
function! lsp#register_server(server_info) abort
    call lsp#log('lsp-core', 'registering server', a:server_info['name'])
    if has_key(s:servers, a:server_info['name'])
        call lsp#log('lsp-core', 'server already registered', a:server_info['name'])
        return -1
    endif
    if !has_key(a:server_info, 'protocol_version')
        call lsp#log('lsp-core', 'protocol_version not specified', a:server_info['name'])
        return -2
    endif
    let l:major_protocol_version = s:parse_major_version(a:server_info['protocol_version'])
    if l:major_protocol_version <= 0
        call lsp#log('lsp-core', 'failed to parse major protocol version', a:server_info['name'], a:server_info['protocol_version'])
        return -3
    endif
    if l:major_protocol_version <= 2
        call lsp#log('lsp-core', 'unsupported protocol version', a:server_info['protocol_version'])
        return -4
    endif
    let s:servers[a:server_info['name']] = {
        \ 'lsp_id': 0,
        \ 'server_info': a:server_info,
        \ 'protocol_version': { 'major': l:major_protocol_version },
        \ }
    call lsp#log('lsp-core', 'registered server', a:server_info['name'], l:major_protocol_version)
    return 1
endfunction

" @params
"   name: name of the server                                        " required
"   options: {                                                      " optional
"       cmd: ['langserver-go'] or {server_info->[]},                " optional, if not found uses server_info['cmd']
"   }
" functions for cmd can be used to use local version of server from node_modules or change path based on windows/*nix
" imagination is your limitation :)
" @returns
"   >=1: server id
"   -100: unregistered server
"   -200: cmd not specified
"   -300: ignore start_server
function! lsp#start_server(name, ...) abort
    if !has_key(s:servers, a:name)
        call lsp#log('lsp-core', 'cannot start unregistered server', a:name)
        return -100
    endif
    let l:server = s:servers[a:name]
    let l:server_info = l:server['server_info']
    if l:server['lsp_id'] > 0
        call lsp#log('lsp-core', 'server already started', a:name)
        return l:server['lsp_id']
    endif
    if len(a:000) == 0
        let l:options = {}
    else
        let l:options = a:0
    endif
    if l:server['protocol_version']['major'] <= 2
        " todo support v2
        throw 'unsupported protocol version'
    else
        if has_key(l:options, 'cmd')
            let l:cmd = type(l:options['cmd']) == type([]) ? l:options['cmd'] : l:options['cmd'](l:server_info)
        elseif has_key(l:server_info, 'cmd')
            let l:cmd = type(l:server_info['cmd']) == type([]) ? l:server_info['cmd'] : l:server_info['cmd'](l:server_info)
        else
            return -200
        endif
        if empty(l:cmd)
            " NOTE: if you don't want to start ther server just return empty for cmd
            call lsp#log('lsp-core', 'ignore starting lsp server for ', a:name)
            return -300
        endif
        " start the server
        let l:lsp_id = lsp#client#start({
            \ 'cmd': l:cmd,
            \ 'on_stderr': function('s:on_stderr'),
            \ 'on_exit': function('s:on_exit'),
            \ 'on_notification': function('s:on_notification'),
            \ })
        if l:lsp_id > 0
            let l:server['lsp_id'] = l:lsp_id
            let s:lsp_id_mappings[l:lsp_id] = a:name
            call lsp#log('lsp-core', 'lsp server started', a:name, l:lsp_id, l:cmd)
            return l:lsp_id
        else
            call lsp#log('lsp-core', 'failed to start lsp', a:name, l:lsp_id)
            return l:lsp_id
        endif
    endif
endfunction

" @returns
"   -2: server not running
"   -1: server not registered
"    1: server force stopped
function! lsp#exit(name) abort
    if !has_key(s:servers, a:name)
        call lsp#log('lsp-core', 'server not registered', a:name)
        return -1
    endif
    let l:server = s:servers[a:name]
    " for now always force exit
    if has_key(l:server, 'lsp_id')
        call lsp#log('lsp-core', 'force exit', a:name, l:server['lsp_id'])
        call lsp#client#stop(l:server['lsp_id'])
        return 1
    else
        call lsp#log('lsp-core', 'server not running', a:name)
        return -2
    endif
endfunction

" @params
"   name: name of the server                                        " required
"   options: {                                                      " optional
"       root_uri: 'file:///tmp/project' or {server_info->root_uri}, " optional , if not found uses server_info['root_uri'], if not found uses s:get_default_root_uri() which internally use cwd()
"   }
" functions for root_uri can be used to find root markers like tsconfig.json.
" imagination is your limitation :)
" @returns
"   >=1: server id
"   -100: unregistered server
"   -201: lsp server not started yet
"   -301: ignore initialize_server
"   -302: ignore initialization
function! lsp#initialize(name, ...) abort
    if !has_key(s:servers, a:name)
        call lsp#log('lsp-core', 'cannot initialize unregistered server', a:name)
        return -100
    endif
    let l:server = s:servers[a:name]
    let l:server_info = l:server['server_info']
    if l:server['lsp_id'] <= 0
        call lsp#log('lsp-core', 'lsp server not started yet', a:name)
        return -201
    endif
    if has_key(l:server, 'init_response')
        call lsp#log('lsp-core', 'lsp server already initialized', a:name)
        return -301
    endif
    if len(a:000) == 0
        let l:options = {}
    else
        let l:options = a:1
    endif
    if has_key(l:options, 'root_uri')
        let l:root_uri = type(l:options['root_uri']) == type('') ? l:options['root_uri'] : l:options['root_uri'](l:server_info)
    elseif has_key(l:server_info, 'root_uri')
        let l:root_uri = type(l:server_info['root_uri']) == type('') ? l:server_info['root_uri'] : l:server_info['root_uri'](l:server_info)
    else
        let l:root_uri = s:get_default_root_uri()
    endif
    if empty(l:root_uri)
        return -302
    endif
    return lsp#client#send_request(l:server['lsp_id'], {
        \ 'method': 'initialize',
        \ 'params': {
        \   'capabilities': {},
        \   'root_uri': l:root_uri,
        \ },
        \ 'on_notification': function('s:on_notification_wrapper', [a:name, l:options])
        \ })
endfunction

function! s:on_stderr(id, data, event) abort
    call lsp#log('lsp-core', 'on_stderr', a:id, a:data)
endfunction

function! s:on_exit(id, data, event) abort
    if has_key(s:lsp_id_mappings, a:id)
        let l:name = s:lsp_id_mappings[a:id]
        let l:server = s:servers[l:name]
        let l:server['lsp_id'] = 0
        if has_key(l:server, 'init_response')
            unlet l:server['init_response']
        endif
        unlet s:lsp_id_mappings[a:id]
        call lsp#log('lsp-core', 'exit', a:id, l:name)
    else
        call lsp#log('lsp-core', 'exit', a:id)
    endif
endfunction

function! s:on_notification(id, data, event) abort
    call lsp#log('lsp-core', 's:on_notification', a:id, a:event, a:data)
    if lsp#client#is_error(a:data)
    elseif lsp#client#is_server_instantiated_notification(a:data)
    else
        let l:request = a:data['request']
        let l:request_method = l:request['method']
        let l:server_name = s:lsp_id_mappings[a:id]
        if l:request_method == 'initialize'
            call s:handle_initialize_notification(a:id, a:data, a:event, l:server_name)
        endif
    endif
endfunction

function s:handle_initialize_notification(id, data, event, server_name) abort
    let s:servers[a:server_name]['init_response'] = a:data['response']['result']
    call lsp#log('lsp-core', 'server initialized', a:server_name)
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

" @return
"   0: failed to parse major version
"   >= 1: parsed major version
" @example
" let s:major_version = s:parse_major_version('2.0')
function! s:parse_major_version(version) abort
    let l:split_version = split(a:version, '\.')
    if len(l:split_version) > 0
        return str2nr(l:split_version[0], 10)
    else
        call lsp#log('lsp-core', 'failed to parse major version', a:version)
        return 0
    endif
endfunction

function! s:get_default_root_uri() abort
    return s:path_to_uri(getcwd())
endfunction

if has('win32') || has('win64')
    function! s:path_to_uri(path) abort
        return 'file://' . substitute(a:path, '\', '/', 'g')
    endfunction
else
    function! s:path_to_uri(path) abort
        return 'file://' . a:path
    endfunction
endif

function! s:on_notification_wrapper(name, options, id, data, event) abort
    if has_key(a:options, 'callback')
        call a:options['callback'](a:name, a:data)
    endif
endfunction
