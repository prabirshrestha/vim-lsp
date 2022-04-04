let s:enabled = 0
let s:already_setup = 0
let s:Stream = lsp#callbag#makeSubject()
" workspace_folders = { 'uri': { uri, name } }
let s:servers = {} " { lsp_id, server_info, workspace_folders, init_callbacks, init_result, buffers: { path: { changed_tick } }
let s:last_command_id = 0
let s:notification_callbacks = [] " { name, callback }

" This hold previous content for each language servers to make
" DidChangeTextDocumentParams. The key is buffer numbers:
"    {
"      1: {
"        "golsp": [ "first-line", "next-line", ... ],
"        "bingo": [ "first-line", "next-line", ... ]
"      },
"      2: {
"        "pyls": [ "first-line", "next-line", ... ]
"      }
"    }
let s:file_content = {}

" do nothing, place it here only to avoid the message
augroup _lsp_silent_
    autocmd!
    autocmd User lsp_setup silent
    autocmd User lsp_register_server silent
    autocmd User lsp_unregister_server silent
    autocmd User lsp_server_init silent
    autocmd User lsp_server_exit silent
    autocmd User lsp_complete_done silent
    autocmd User lsp_float_opened silent
    autocmd User lsp_float_closed silent
    autocmd User lsp_float_focused silent
    autocmd User lsp_buffer_enabled silent
    autocmd User lsp_diagnostics_updated silent
    autocmd User lsp_progress_updated silent
augroup END

function! lsp#log_verbose(...) abort
    if g:lsp_log_verbose
        call call(function('lsp#log'), a:000)
    endif
endfunction

function! lsp#log(...) abort
    if !empty(g:lsp_log_file)
        call writefile([strftime('%c') . ':' . json_encode(a:000)], g:lsp_log_file, 'a')
    endif
endfunction

function! lsp#enable() abort
    if s:enabled
        return
    endif
    if !s:already_setup
        doautocmd <nomodeline> User lsp_setup
        let s:already_setup = 1
    endif
    let s:enabled = 1
    if g:lsp_signature_help_enabled
        call lsp#ui#vim#signature_help#setup()
    endif
    call lsp#ui#vim#completion#_setup()
    call lsp#internal#document_highlight#_enable()
    call lsp#internal#diagnostics#_enable()
    call lsp#internal#document_code_action#signs#_enable()
    call lsp#internal#show_message_request#_enable()
    call lsp#internal#show_message#_enable()
    call lsp#internal#work_done_progress#_enable()
    call lsp#internal#completion#documentation#_enable()
    call s:register_events()
endfunction

function! lsp#disable() abort
    if !s:enabled
        return
    endif
    call lsp#ui#vim#signature_help#_disable()
    call lsp#ui#vim#completion#_disable()
    call lsp#internal#document_highlight#_disable()
    call lsp#internal#diagnostics#_disable()
    call lsp#internal#document_code_action#signs#_disable()
    call lsp#internal#show_message_request#_disable()
    call lsp#internal#show_message#_disable()
    call lsp#internal#work_done_progress#_disable()
    call lsp#internal#completion#documentation#_disable()
    call s:unregister_events()
    let s:enabled = 0
endfunction

function! lsp#get_server_names() abort
    return keys(s:servers)
endfunction

function! lsp#get_server_info(server_name) abort
    return s:servers[a:server_name]['server_info']
endfunction

function! lsp#get_server_root_uri(server_name) abort
    return get(s:servers[a:server_name]['server_info'], '_root_uri_resolved', '')
endfunction

function! lsp#get_server_capabilities(server_name) abort
    let l:server = s:servers[a:server_name]
    return has_key(l:server, 'init_result') ? l:server['init_result']['result']['capabilities'] : {}
endfunction

function! s:server_status(server_name) abort
    if !has_key(s:servers, a:server_name)
        return 'unknown server'
    endif
    let l:server = s:servers[a:server_name]
    if has_key(l:server, 'exited')
        return 'exited'
    endif
    if has_key(l:server, 'init_callbacks')
        return 'starting'
    endif
    if has_key(l:server, 'failed')
        return 'failed'
    endif
    if has_key(l:server, 'init_result')
        return 'running'
    endif
    return 'not running'
endfunction

" Returns the current status of all servers (if called with no arguments) or
" the given server (if given an argument). Can be one of "unknown server",
" "exited", "starting", "failed", "running", "not running"
function! lsp#get_server_status(...) abort
    if a:0 == 0
        let l:strs = map(keys(s:servers), {k, v -> v . ': ' . s:server_status(v)})
        return join(l:strs, "\n")
    else
        return s:server_status(a:1)
    endif
endfunction

let s:color_map = {
\ 'exited': 'Error',
\ 'starting': 'MoreMsg',
\ 'failed': 'WarningMsg',
\ 'running': 'Keyword',
\ 'not running': 'Comment'
\}

" Print the current status of all servers (if called with no arguments)
function! lsp#print_server_status() abort
    for l:k in sort(keys(s:servers))
        let l:status = s:server_status(l:k)
        echon l:k . ': '
        exec 'echohl' s:color_map[l:status]
        echon l:status
        echohl None
        echo ''
    endfor
endfunction

" @params {server_info} = {
"   'name': 'go-langserver',        " required, must be unique
"   'allowlist': ['go'],            " optional, array of filetypes to allow, * for all filetypes
"   'blocklist': [],                " optional, array of filetypes to block, * for all filetypes,
"   'cmd': {server_info->['go-langserver]} " function that takes server_info and returns array of cmd and args, return empty if you don't want to start the server
" }
function! lsp#register_server(server_info) abort
    let l:server_name = a:server_info['name']
    if has_key(s:servers, l:server_name)
        call lsp#log('lsp#register_server', 'server already registered', l:server_name)
    endif
    " NOTE: workspace_folders is dict for faster lookup instead of array
    let s:servers[l:server_name] = {
        \ 'server_info': a:server_info,
        \ 'lsp_id': 0,
        \ 'buffers': {},
        \ 'workspace_folders': {},
        \ }
    call lsp#log('lsp#register_server', 'server registered', l:server_name)
    doautocmd <nomodeline> User lsp_register_server
endfunction

"
" lsp#register_command
"
" @param {command_name} = string
" @param {callback} = funcref
"
function! lsp#register_command(command_name, callback) abort
    call lsp#ui#vim#execute_command#_register(a:command_name, a:callback)
endfunction

function! lsp#register_notifications(name, callback) abort
    call add(s:notification_callbacks, { 'name': a:name, 'callback': a:callback })
endfunction

function! lsp#unregister_notifications(name) abort
    " TODO
endfunction

function! lsp#stop_server(server_name) abort
    if has_key(s:servers, a:server_name) && s:servers[a:server_name]['lsp_id'] > 0
        call lsp#client#stop(s:servers[a:server_name]['lsp_id'])
    endif
endfunction

function! s:register_events() abort
    augroup lsp
        autocmd!
        autocmd BufNewFile * call s:on_text_document_did_open()
        autocmd BufReadPost * call s:on_text_document_did_open()
        autocmd BufWritePost * call s:on_text_document_did_save()
        autocmd BufWinLeave * call s:on_text_document_did_close()
        autocmd BufWipeout * call s:on_buf_wipeout(expand('<afile>'))
        autocmd InsertLeave * call s:on_text_document_did_change()
        autocmd TextChanged * call s:on_text_document_did_change()
        if exists('##TextChangedP')
            autocmd TextChangedP * call s:on_text_document_did_change()
        endif
        if g:lsp_untitled_buffer_enabled
            autocmd FileType * call s:on_filetype_changed(bufnr(expand('<afile>')))
        endif
    augroup END

    for l:bufnr in range(1, bufnr('$'))
        if bufexists(l:bufnr) && bufloaded(l:bufnr)
            call s:on_text_document_did_open(l:bufnr)
        endif
    endfor
endfunction

function! s:unregister_events() abort
    augroup lsp
        autocmd!
    augroup END
    doautocmd <nomodeline> User lsp_unregister_server
endfunction

function! s:on_filetype_changed(buf) abort
  call s:on_buf_wipeout(a:buf)
  " TODO: stop unused servers
  call s:on_text_document_did_open()
endfunction

function! s:on_text_document_did_open(...) abort
    let l:buf = a:0 > 0 ? a:1 : bufnr('%')
    if getbufvar(l:buf, '&buftype') ==# 'terminal' | return | endif
    if getcmdwintype() !=# '' | return | endif
    call lsp#log('s:on_text_document_did_open()', l:buf, &filetype, getcwd(), lsp#utils#get_buffer_uri(l:buf))

    " Some language server notify diagnostics to the buffer that has not been loaded yet.
    " This diagnostics was stored `autoload/lsp/internal/diagnostics/state.vim` but not highlighted.
    " So we should refresh highlights when buffer opened.
    call lsp#internal#diagnostics#state#_force_notify_buffer(l:buf)

    for l:server_name in lsp#get_allowed_servers(l:buf)
        call s:ensure_flush(l:buf, l:server_name, function('s:fire_lsp_buffer_enabled', [l:server_name, l:buf]))
    endfor
endfunction

function! lsp#activate() abort
  call s:on_text_document_did_open()
endfunction

function! s:on_text_document_did_save() abort
    let l:buf = bufnr('%')
    if getbufvar(l:buf, '&buftype') ==# 'terminal' | return | endif
    call lsp#log('s:on_text_document_did_save()', l:buf)
    for l:server_name in lsp#get_allowed_servers(l:buf)
        if g:lsp_text_document_did_save_delay >= 0
            " We delay the callback by one loop iteration as calls to ensure_flush
            " can introduce mmap'd file locks that linger on Windows and collide
            " with the second lang server call preventing saves (see #455)
            call s:ensure_flush(l:buf, l:server_name, {result->timer_start(g:lsp_text_document_did_save_delay, {timer->s:call_did_save(l:buf, l:server_name, result, function('s:Noop'))})})
        else
            call s:ensure_flush(l:buf, l:server_name, {result->s:call_did_save(l:buf, l:server_name, result, function('s:Noop'))})
        endif
    endfor
endfunction

function! s:on_text_document_did_change() abort
    let l:buf = bufnr('%')
    if getbufvar(l:buf, '&buftype') ==# 'terminal' | return | endif
    call lsp#log('s:on_text_document_did_change()', l:buf)
    call s:add_didchange_queue(l:buf)
endfunction

function! s:call_did_save(buf, server_name, result, cb) abort
    if lsp#client#is_error(a:result['response'])
        return
    endif

    let l:server = s:servers[a:server_name]
    let l:path = lsp#utils#get_buffer_uri(a:buf)

    let [l:supports_did_save, l:did_save_options] = lsp#capabilities#get_text_document_save_registration_options(a:server_name)
    if !l:supports_did_save
        let l:msg = s:new_rpc_success('---> ignoring textDocument/didSave. not supported by server', { 'server_name': a:server_name, 'path': l:path })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    call s:update_file_content(a:buf, a:server_name, lsp#utils#buffer#_get_lines(a:buf))

    let l:buffers = l:server['buffers']
    let l:buffer_info = l:buffers[l:path]

    let l:params = {
        \ 'textDocument': s:get_text_document_identifier(a:buf),
        \ }

    if l:did_save_options['includeText']
        let l:params['text'] = s:get_text_document_text(a:buf, a:server_name)
    endif
    call s:send_notification(a:server_name, {
        \ 'method': 'textDocument/didSave',
        \ 'params': l:params,
        \ })

    let l:msg = s:new_rpc_success('textDocument/didSave sent', { 'server_name': a:server_name, 'path': l:path })
    call lsp#log(l:msg)
    call a:cb(l:msg)
endfunction

function! s:on_text_document_did_close() abort
    let l:buf = bufnr('%')
    if getbufvar(l:buf, '&buftype') ==# 'terminal' | return | endif
    call lsp#log('s:on_text_document_did_close()', l:buf)
endfunction

function! s:get_last_file_content(buf, server_name) abort
    if has_key(s:file_content, a:buf) && has_key(s:file_content[a:buf], a:server_name)
        return s:file_content[a:buf][a:server_name]
    endif
    return []
endfunction

function! s:update_file_content(buf, server_name, new) abort
    if !has_key(s:file_content, a:buf)
        let s:file_content[a:buf] = {}
    endif
    call lsp#log('s:update_file_content()', a:buf)
    let s:file_content[a:buf][a:server_name] = a:new
endfunction

function! s:on_buf_wipeout(buf) abort
    if has_key(s:file_content, a:buf)
        call remove(s:file_content, a:buf)
    endif
endfunction

function! s:ensure_flush_all(buf, server_names) abort
    for l:server_name in a:server_names
        call s:ensure_flush(a:buf, l:server_name, function('s:Noop'))
    endfor
endfunction

function! s:fire_lsp_buffer_enabled(server_name, buf, ...) abort
    if a:buf == bufnr('%')
        doautocmd <nomodeline> User lsp_buffer_enabled
    else
        " Not using ++once in autocmd for compatibility of VIM8.0
        let l:cmd = printf('autocmd BufEnter <buffer=%d> doautocmd <nomodeline> User lsp_buffer_enabled', a:buf)
        exec printf('augroup _lsp_fire_buffer_enabled | exec "%s | autocmd! _lsp_fire_buffer_enabled BufEnter <buffer>" | augroup END', l:cmd)
    endif
endfunction

function! s:Noop(...) abort
endfunction

function! s:is_step_error(s) abort
    return lsp#client#is_error(a:s.result[0]['response'])
endfunction

function! s:throw_step_error(s) abort
    call a:s.callback(a:s.result[0])
endfunction

function! s:new_rpc_success(message, data) abort
    return {
        \ 'response': {
        \   'message': a:message,
        \   'data': extend({ '__data__': 'vim-lsp'}, a:data),
        \ }
        \ }
endfunction

function! s:new_rpc_error(message, data) abort
    return {
        \ 'response': {
        \   'error': {
        \       'code': 0,
        \       'message': a:message,
        \       'data': extend({ '__error__': 'vim-lsp'}, a:data),
        \   },
        \ }
        \ }
endfunction

function! s:ensure_flush(buf, server_name, cb) abort
    call lsp#utils#step#start([
        \ {s->s:ensure_start(a:buf, a:server_name, s.callback)},
        \ {s->s:is_step_error(s) ? s:throw_step_error(s) : s:ensure_init(a:buf, a:server_name, s.callback)},
        \ {s->s:is_step_error(s) ? s:throw_step_error(s) : s:ensure_conf(a:buf, a:server_name, s.callback)},
        \ {s->s:is_step_error(s) ? s:throw_step_error(s) : s:ensure_open(a:buf, a:server_name, s.callback)},
        \ {s->s:is_step_error(s) ? s:throw_step_error(s) : s:ensure_changed(a:buf, a:server_name, s.callback)},
        \ {s->a:cb(s.result[0])}
        \ ])
endfunction

function! s:ensure_start(buf, server_name, cb) abort
    let l:path = lsp#utils#get_buffer_path(a:buf)

    if lsp#utils#is_remote_uri(l:path)
        let l:msg = s:new_rpc_error('ignoring start server due to remote uri', { 'server_name': a:server_name, 'uri': l:path})
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    if l:server['lsp_id'] > 0
        let l:msg = s:new_rpc_success('server already started', { 'server_name': a:server_name })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    if has_key(l:server_info, 'tcp')
        let l:tcp = l:server_info['tcp'](l:server_info)
        let l:lsp_id = lsp#client#start({
            \ 'tcp': l:tcp,
            \ 'on_stderr': function('s:on_stderr', [a:server_name]),
            \ 'on_exit': function('s:on_exit', [a:server_name]),
            \ 'on_notification': function('s:on_notification', [a:server_name]),
            \ 'on_request': function('s:on_request', [a:server_name]),
            \ })
    elseif has_key(l:server_info, 'cmd')
        let l:cmd_type = type(l:server_info['cmd'])
        if l:cmd_type == v:t_list
            let l:cmd = l:server_info['cmd']
        else
            let l:cmd = l:server_info['cmd'](l:server_info)
        endif

        if empty(l:cmd)
            let l:msg = s:new_rpc_error('ignore server start since cmd is empty', { 'server_name': a:server_name })
            call lsp#log(l:msg)
            call a:cb(l:msg)
            return
        endif

        call lsp#log('Starting server', a:server_name, l:cmd)
        let l:opts = {
        \ 'cmd': l:cmd,
        \ 'on_stderr': function('s:on_stderr', [a:server_name]),
        \ 'on_exit': function('s:on_exit', [a:server_name]),
        \ 'on_notification': function('s:on_notification', [a:server_name]),
        \ 'on_request': function('s:on_request', [a:server_name]),
        \ }
        if has_key(l:server_info, 'env')
          let l:opts.env = l:server_info.env
        endif
        let l:lsp_id = lsp#client#start(l:opts)
    endif

    if l:lsp_id > 0
        let l:server['lsp_id'] = l:lsp_id
        let l:msg = s:new_rpc_success('started lsp server successfully', { 'server_name': a:server_name, 'lsp_id': l:lsp_id })
        call lsp#log(l:msg)
        call a:cb(l:msg)
    else
        let l:msg = s:new_rpc_error('failed to start server', { 'server_name': a:server_name, 'cmd': l:cmd })
        call lsp#log(l:msg)
        call a:cb(l:msg)
    endif
endfunction

function! lsp#default_get_supported_capabilities(server_info) abort
    " Sorted alphabetically
    return {
    \   'textDocument': {
    \       'codeAction': {
    \         'dynamicRegistration': v:false,
    \         'codeActionLiteralSupport': {
    \           'codeActionKind': {
    \             'valueSet': ['', 'quickfix', 'refactor', 'refactor.extract', 'refactor.inline', 'refactor.rewrite', 'source', 'source.organizeImports'],
    \           }
    \         },
    \         'isPreferredSupport': v:true,
    \         'disabledSupport': v:true,
    \       },
    \       'codeLens': {
    \           'dynamicRegistration': v:false,
    \       },
    \       'completion': {
    \           'dynamicRegistration': v:false,
    \           'completionItem': {
    \              'documentationFormat': ['markdown', 'plaintext'],
    \              'snippetSupport': v:false,
    \              'resolveSupport': {
    \                  'properties': ['additionalTextEdits']
    \              }
    \           },
    \           'completionItemKind': {
    \              'valueSet': lsp#omni#get_completion_item_kinds()
    \           }
    \       },
    \       'declaration': {
    \           'dynamicRegistration': v:false,
    \           'linkSupport' : v:true
    \       },
    \       'definition': {
    \           'dynamicRegistration': v:false,
    \           'linkSupport' : v:true
    \       },
    \       'documentHighlight': {
    \           'dynamicRegistration': v:false,
    \       },
    \       'documentSymbol': {
    \           'dynamicRegistration': v:false,
    \           'symbolKind': {
    \              'valueSet': lsp#ui#vim#utils#get_symbol_kinds()
    \           },
    \           'hierarchicalDocumentSymbolSupport': v:false,
    \           'labelSupport': v:false
    \       },
    \       'foldingRange': {
    \           'dynamicRegistration': v:false,
    \           'lineFoldingOnly': v:true,
    \           'rangeLimit': 5000,
    \       },
    \       'formatting': {
    \           'dynamicRegistration': v:false,
    \       },
    \       'hover': {
    \           'dynamicRegistration': v:false,
    \           'contentFormat': ['markdown', 'plaintext'],
    \       },
    \       'implementation': {
    \           'dynamicRegistration': v:false,
    \           'linkSupport' : v:true
    \       },
    \       'rangeFormatting': {
    \           'dynamicRegistration': v:false,
    \       },
    \       'references': {
    \           'dynamicRegistration': v:false,
    \       },
    \       'semanticHighlightingCapabilities': {
    \           'semanticHighlighting': lsp#ui#vim#semantic#is_enabled()
    \       },
    \       'publishDiagnostics': {
    \           'relatedInformation': v:true,
    \       },
    \       'synchronization': {
    \           'didSave': v:true,
    \           'dynamicRegistration': v:false,
    \           'willSave': v:false,
    \           'willSaveWaitUntil': v:false,
    \       },
    \       'typeHierarchy': v:false,
    \       'typeDefinition': {
    \           'dynamicRegistration': v:false,
    \           'linkSupport' : v:true
    \       },
    \   },
    \   'window': {
    \       'workDoneProgress': g:lsp_work_done_progress_enabled ? v:true : v:false,
    \   },
    \   'workspace': {
    \       'applyEdit': v:true,
    \       'configuration': v:true,
    \       'workspaceFolders': g:lsp_experimental_workspace_folders ? v:true : v:false,
    \   },
    \ }
endfunction

function! s:ensure_init(buf, server_name, cb) abort
    let l:server = s:servers[a:server_name]

    if has_key(l:server, 'init_result')
        let l:msg = s:new_rpc_success('lsp server already initialized', { 'server_name': a:server_name, 'init_result': l:server['init_result'] })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    if has_key(l:server, 'init_callbacks')
        " waiting for initialize response
        call add(l:server['init_callbacks'], a:cb)
        let l:msg = s:new_rpc_success('waiting for lsp server to initialize', { 'server_name': a:server_name })
        call lsp#log(l:msg)
        return
    endif

    " server has already started, but not initialized

    let l:server_info = l:server['server_info']
    let l:root_uri = has_key(l:server_info, 'root_uri') ?  l:server_info['root_uri'](l:server_info) : ''
    if empty(l:root_uri)
        let l:msg = s:new_rpc_error('ignore initialization lsp server due to empty root_uri', { 'server_name': a:server_name, 'lsp_id': l:server['lsp_id'] })
        call lsp#log(l:msg)
        let l:root_uri = lsp#utils#get_default_root_uri()
    endif
    let l:server['server_info']['_root_uri_resolved'] = l:root_uri
    let l:server['workspace_folders'][l:root_uri] = { 'name': l:root_uri, 'uri': l:root_uri }

    if has_key(l:server_info, 'capabilities')
        let l:capabilities = l:server_info['capabilities']
    else
        let l:capabilities = call(g:lsp_get_supported_capabilities[0], [l:server_info])
    endif

    let l:request = {
    \   'method': 'initialize',
    \   'params': {
    \     'processId': getpid(),
    \     'clientInfo': { 'name': 'vim-lsp' },
    \     'capabilities': l:capabilities,
    \     'rootUri': l:root_uri,
    \     'rootPath': lsp#utils#uri_to_path(l:root_uri),
    \     'trace': 'off',
    \   },
    \ }
    
    let l:workspace_capabilities = get(l:capabilities, 'workspace', {})
    if get(l:workspace_capabilities, 'workspaceFolders', v:false)
        " TODO: extract folder name for l:root_uri
        let l:server_info['workspaceFolders'] = [
            \ { 'uri': l:root_uri, 'name': l:root_uri }
            \ ]
        let l:request['params']['workspaceFolders'] = l:server_info['workspaceFolders']
    endif

    if has_key(l:server_info, 'initialization_options')
        let l:request.params['initializationOptions'] = l:server_info['initialization_options']
    endif

    let l:server['init_callbacks'] = [a:cb]

    call s:send_request(a:server_name, l:request)
endfunction

function! s:ensure_conf(buf, server_name, cb) abort
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    if has_key(l:server_info, 'workspace_config') && !get(l:server_info, '_workspace_config_sent', v:false)
        let l:server_info['_workspace_config_sent'] = v:true
        call s:send_notification(a:server_name, {
            \ 'method': 'workspace/didChangeConfiguration',
            \ 'params': {
            \   'settings': l:server_info['workspace_config'],
            \ }
            \ })
    endif
    let l:msg = s:new_rpc_success('configuration sent', { 'server_name': a:server_name })
    call lsp#log(l:msg)
    call a:cb(l:msg)
endfunction

function! s:text_changes(buf, server_name) abort
    let l:sync_kind = lsp#capabilities#get_text_document_change_sync_kind(a:server_name)
    " When syncKind is None, return null for contentChanges.
    if l:sync_kind == 0
        return v:null
    endif

    " When syncKind is Incremental and previous content is saved.
    if l:sync_kind == 2 && has_key(s:file_content, a:buf)
        " compute diff
        let l:old_content = s:get_last_file_content(a:buf, a:server_name)
        let l:new_content = lsp#utils#buffer#_get_lines(a:buf)
        let l:changes = lsp#utils#diff#compute(l:old_content, l:new_content)
        if empty(l:changes.text) && l:changes.rangeLength ==# 0
            return []
        endif
        call s:update_file_content(a:buf, a:server_name, l:new_content)
        return [l:changes]
    endif

    let l:new_content = lsp#utils#buffer#_get_lines(a:buf)
    let l:changes = {'text': join(l:new_content, "\n")}
    call s:update_file_content(a:buf, a:server_name, l:new_content)
    return [l:changes]
endfunction

function! s:ensure_changed(buf, server_name, cb) abort
    let l:server = s:servers[a:server_name]
    let l:path = lsp#utils#get_buffer_uri(a:buf)

    let l:buffers = l:server['buffers']
    if !has_key(l:buffers, l:path)
        let l:msg = s:new_rpc_success('file is not managed', { 'server_name': a:server_name, 'path': l:path })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif
    let l:buffer_info = l:buffers[l:path]

    let l:changed_tick = getbufvar(a:buf, 'changedtick')

    if l:buffer_info['changed_tick'] == l:changed_tick
        let l:msg = s:new_rpc_success('not dirty', { 'server_name': a:server_name, 'path': l:path })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    let l:buffer_info['changed_tick'] = l:changed_tick
    let l:buffer_info['version'] = l:buffer_info['version'] + 1

    call s:send_notification(a:server_name, {
        \ 'method': 'textDocument/didChange',
        \ 'params': {
        \   'textDocument': s:get_versioned_text_document_identifier(a:buf, l:buffer_info),
        \   'contentChanges': s:text_changes(a:buf, a:server_name),
        \ }
        \ })
    call lsp#ui#vim#folding#send_request(a:server_name, a:buf, 0)

    let l:msg = s:new_rpc_success('textDocument/didChange sent', { 'server_name': a:server_name, 'path': l:path })
    call lsp#log(l:msg)
    call a:cb(l:msg)
endfunction

function! s:ensure_open(buf, server_name, cb) abort
    let l:server = s:servers[a:server_name]
    let l:path = lsp#utils#get_buffer_uri(a:buf)

    if empty(l:path)
        let l:msg = s:new_rpc_success('ignore open since not a valid uri', { 'server_name': a:server_name, 'path': l:path })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    let l:buffers = l:server['buffers']

    if has_key(l:buffers, l:path)
        let l:msg = s:new_rpc_success('already opened', { 'server_name': a:server_name, 'path': l:path })
        call lsp#log(l:msg)
        call a:cb(l:msg)
        return
    endif

    if lsp#capabilities#has_workspace_folders_change_notifications(a:server_name)
        call s:workspace_add_folder(a:server_name)
    endif

    call s:update_file_content(a:buf, a:server_name, lsp#utils#buffer#_get_lines(a:buf))

    let l:buffer_info = { 'changed_tick': getbufvar(a:buf, 'changedtick'), 'version': 1, 'uri': l:path }
    let l:buffers[l:path] = l:buffer_info

    call s:send_notification(a:server_name, {
        \ 'method': 'textDocument/didOpen',
        \ 'params': {
        \   'textDocument': s:get_text_document(a:buf, a:server_name, l:buffer_info)
        \ },
        \ })

    call lsp#ui#vim#folding#send_request(a:server_name, a:buf, 0)

    let l:msg = s:new_rpc_success('textDocument/open sent', { 'server_name': a:server_name, 'path': l:path, 'filetype': getbufvar(a:buf, '&filetype') })
    call lsp#log(l:msg)
    call a:cb(l:msg)
endfunction

function! s:workspace_add_folder(server_name) abort
    if !g:lsp_experimental_workspace_folders | return | endif
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    let l:root_uri = has_key(l:server_info, 'root_uri') ?  l:server_info['root_uri'](l:server_info) : lsp#utils#get_default_root_uri()
    if !has_key(l:server['workspace_folders'], l:root_uri)
        let l:workspace_folder = { 'name': l:root_uri, 'uri': l:root_uri }
        call lsp#log('adding workspace folder', a:server_name, l:workspace_folder)
        call s:send_notification(a:server_name, {
            \ 'method': 'workspace/didChangeWorkspaceFolders',
            \ 'params': {
            \    'added': [l:workspace_folder],
            \  }
            \ })
        let l:server['workspace_folders'][l:root_uri] = l:workspace_folder
    endif
endfunction

function! s:send_request(server_name, data) abort
    let l:lsp_id = s:servers[a:server_name]['lsp_id']
    let l:data = copy(a:data)
    if has_key(l:data, 'on_notification')
        let l:data['on_notification'] = '---funcref---'
    endif
    call lsp#log_verbose('--->', l:lsp_id, a:server_name, l:data)
    return lsp#client#send_request(l:lsp_id, a:data)
endfunction

function! s:send_notification(server_name, data) abort
    let l:lsp_id = s:servers[a:server_name]['lsp_id']
    let l:data = copy(a:data)
    if has_key(l:data, 'on_notification')
        let l:data['on_notification'] = '---funcref---'
    endif
    call lsp#log_verbose('--->', l:lsp_id, a:server_name, l:data)
    call lsp#client#send_notification(l:lsp_id, a:data)
endfunction

function! s:send_response(server_name, data) abort
    let l:lsp_id = s:servers[a:server_name]['lsp_id']
    let l:data = copy(a:data)
    call lsp#log_verbose('--->', l:lsp_id, a:server_name, l:data)
    call lsp#client#send_response(l:lsp_id, a:data)
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
        let l:server['exited'] = 1
        if has_key(l:server, 'init_result')
            unlet l:server['init_result']
        endif
        let l:server['workspace_folders'] = {}
        call lsp#stream(1, { 'server': '$vimlsp',
            \ 'response': { 'method': '$/vimlsp/lsp_server_exit', 'params': { 'server': a:server_name } } })
        doautocmd <nomodeline> User lsp_server_exit
    endif
endfunction

function! s:on_notification(server_name, id, data, event) abort
    call lsp#log_verbose('<---', a:id, a:server_name, a:data)
    let l:response = a:data['response']
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']

    let l:stream_data = { 'server': a:server_name, 'response': l:response }
    if has_key(a:data, 'request')
        let l:stream_data['request'] = a:data['request']
    endif
    call lsp#stream(1, l:stream_data) " notify stream before callbacks

    if lsp#client#is_server_instantiated_notification(a:data)
        if has_key(l:response, 'method')
            if l:response['method'] ==# 'textDocument/semanticHighlighting'
                call lsp#ui#vim#semantic#handle_semantic(a:server_name, a:data)
            endif
            " NOTE: this is legacy code, use stream instead of handling notifications here
        endif
    else
        let l:request = a:data['request']
        let l:method = l:request['method']
        if l:method ==# 'initialize'
            call s:handle_initialize(a:server_name, a:data)
        endif
    endif

    for l:callback_info in s:notification_callbacks
        call l:callback_info.callback(a:server_name, a:data)
    endfor
endfunction

function! s:on_request(server_name, id, request) abort
    call lsp#log_verbose('<---', 's:on_request', a:id, a:request)

    let l:stream_data = { 'server': a:server_name, 'request': a:request }
    call lsp#stream(1, l:stream_data) " notify stream before callbacks

    if a:request['method'] ==# 'workspace/applyEdit'
        call lsp#utils#workspace_edit#apply_workspace_edit(a:request['params']['edit'])
        call s:send_response(a:server_name, { 'id': a:request['id'], 'result': { 'applied': v:true } })
    elseif a:request['method'] ==# 'workspace/configuration'
        let l:response_items = map(a:request['params']['items'], { key, val -> lsp#utils#workspace_config#get_value(a:server_name, val) })
        call s:send_response(a:server_name, { 'id': a:request['id'], 'result': l:response_items })
    elseif a:request['method'] ==# 'window/workDoneProgress/create'
        call s:send_response(a:server_name, { 'id': a:request['id'], 'result': v:null})
    else
        " TODO: for now comment this out until we figure out a better solution.
        " We need to comment this out so that others outside of vim-lsp can
        " hook into the stream and provide their own response.
        " " Error returned according to json-rpc specification.
        " call s:send_response(a:server_name, { 'id': a:request['id'], 'error': { 'code': -32601, 'message': 'Method not found' } })
    endif
endfunction

function! s:handle_initialize(server_name, data) abort
    let l:response = a:data['response']
    let l:server = s:servers[a:server_name]

    if has_key(l:server, 'exited')
        unlet l:server['exited']
    endif

    let l:init_callbacks = l:server['init_callbacks']
    unlet l:server['init_callbacks']

    if !lsp#client#is_error(l:response)
        let l:server['init_result'] = l:response
        " Delete cache of trigger chars
        if has_key(b:, 'lsp_signature_help_trigger_character')
            unlet b:lsp_signature_help_trigger_character
        endif
    else
        let l:server['failed'] = l:response['error']
        call lsp#utils#error('Failed to initialize ' . a:server_name . ' with error ' . l:response['error']['code'] . ': ' . l:response['error']['message'])
    endif

    call s:send_notification(a:server_name, { 'method': 'initialized', 'params': {} })

    for l:Init_callback in l:init_callbacks
        call l:Init_callback(a:data)
    endfor

    doautocmd <nomodeline> User lsp_server_init
endfunction

function! lsp#get_whitelisted_servers(...) abort
    return call(function('lsp#get_allowed_servers'), a:000)
endfunction

" call lsp#get_allowed_servers()
" call lsp#get_allowed_servers(bufnr('%'))
" call lsp#get_allowed_servers('typescript')
function! lsp#get_allowed_servers(...) abort
    if a:0 == 0
        let l:buffer_filetype = &filetype
    else
        if type(a:1) == type('')
            let l:buffer_filetype = a:1
        else
            let l:buffer_filetype = getbufvar(a:1, '&filetype')
        endif
    endif

    " TODO: cache active servers per buffer
    let l:active_servers = []

    for l:server_name in keys(s:servers)
        let l:server_info = s:servers[l:server_name]['server_info']
        let l:blocked = 0

        if has_key(l:server_info, 'blocklist')
            let l:blocklistkey = 'blocklist'
        else
            let l:blocklistkey = 'blacklist'
        endif
        if has_key(l:server_info, l:blocklistkey)
            for l:filetype in l:server_info[l:blocklistkey]
                if l:filetype ==? l:buffer_filetype || l:filetype ==# '*'
                    let l:blocked = 1
                    break
                endif
            endfor
        endif

        if l:blocked
            continue
        endif

        if has_key(l:server_info, 'allowlist')
            let l:allowlistkey = 'allowlist'
        else
            let l:allowlistkey = 'whitelist'
        endif
        if has_key(l:server_info, l:allowlistkey)
            for l:filetype in l:server_info[l:allowlistkey]
                if l:filetype ==? l:buffer_filetype || l:filetype ==# '*'
                    let l:active_servers += [l:server_name]
                    break
                endif
            endfor
        endif
    endfor

    return l:active_servers
endfunction

function! s:get_text_document_text(buf, server_name) abort
    return join(s:get_last_file_content(a:buf, a:server_name), "\n")
endfunction

function! s:get_text_document(buf, server_name, buffer_info) abort
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    let l:language_id = has_key(l:server_info, 'languageId') ?  l:server_info['languageId'](l:server_info) : &filetype
    return {
        \ 'uri': lsp#utils#get_buffer_uri(a:buf),
        \ 'languageId': l:language_id,
        \ 'version': a:buffer_info['version'],
        \ 'text': s:get_text_document_text(a:buf, a:server_name),
        \ }
endfunction

function! lsp#get_text_document_identifier(...) abort
    let l:buf = a:0 > 0 ? a:1 : bufnr('%')
    return { 'uri': lsp#utils#get_buffer_uri(l:buf) }
endfunction

function! lsp#get_position(...) abort
    let l:line = line('.')
    let l:char = lsp#utils#to_char('%', l:line, col('.'))
    return { 'line': l:line - 1, 'character': l:char }
endfunction

function! s:get_text_document_identifier(buf) abort
    return { 'uri': lsp#utils#get_buffer_uri(a:buf) }
endfunction

function! s:get_versioned_text_document_identifier(buf, buffer_info) abort
    return {
        \ 'uri': lsp#utils#get_buffer_uri(a:buf),
        \ 'version': a:buffer_info['version'],
        \ }
endfunction

" lsp#stream {{{
"
" example 1:
"
" function! s:on_textDocumentDiagnostics(x) abort
"   echom 'Diagnostics for ' . a:x['server'] . ' ' . json_encode(a:x['response'])
" endfunction
"
" au User lsp_setup call lsp#callbag#pipe(
"    \ lsp#stream(),
"    \ lsp#callbag#filter({x-> has_key(x, 'response') && !has_key(x['response'], 'error') && get(x['response'], 'method', '') == 'textDocument/publishDiagnostics'}),
"    \ lsp#callbag#subscribe({ 'next':{x->s:on_textDocumentDiagnostics(x)} }),
"    \ )
"
" example 2:
" call lsp#stream(1, { 'command': 'DocumentFormat' })
function! lsp#stream(...) abort
    if a:0 == 0
        return lsp#callbag#share(s:Stream)
    else
        call s:Stream(a:1, a:2)
    endif
endfunction
" }}}

" lsp#request {{{
function! lsp#request(server_name, request) abort
    let l:ctx = {
        \ 'server_name': a:server_name,
        \ 'request': copy(a:request),
        \ 'request_id': 0,
        \ 'done': 0,
        \ 'cancelled': 0,
        \ }
    return lsp#callbag#create(function('s:request_create', [l:ctx]))
endfunction

function! s:request_create(ctx, next, error, complete) abort
    let a:ctx['next'] = a:next
    let a:ctx['error'] = a:error
    let a:ctx['complete'] = a:complete
    let a:ctx['bufnr'] = get(a:ctx['request'], 'bufnr', bufnr('%'))
    let a:ctx['request']['on_notification'] = function('s:request_on_notification', [a:ctx])
    call lsp#utils#step#start([
        \ {s->s:ensure_flush(a:ctx['bufnr'], a:ctx['server_name'], s.callback)},
        \ {s->s:is_step_error(s) ? s:request_error(a:ctx, s.result[0]) : s:request_send(a:ctx) },
        \ ])
    return function('s:request_cancel', [a:ctx])
endfunction

function! s:request_send(ctx) abort
    if a:ctx['cancelled'] | return | endif " caller already unsubscribed so don't bother sending request
    let a:ctx['request_id'] = s:send_request(a:ctx['server_name'], a:ctx['request'])
endfunction

function! s:request_error(ctx, error) abort
    if a:ctx['cancelled'] | return | endif " caller already unsubscribed so don't bother notifying
    let a:ctx['done'] = 1
    call a:ctx['error'](a:error)
endfunction

function! s:request_on_notification(ctx, id, data, event) abort
    if a:ctx['cancelled'] | return | endif " caller already unsubscribed so don't bother notifying
    let a:ctx['done'] = 1
    call a:ctx['next'](extend({ 'server_name': a:ctx['server_name'] }, a:data))
    call a:ctx['complete']()
endfunction

function! s:request_cancel(ctx) abort
    if a:ctx['cancelled'] | return | endif
    let a:ctx['cancelled'] = 1
    if a:ctx['request_id'] <= 0 || a:ctx['done'] | return | endif " we have not made the request yet or request is complete, so nothing to cancel
    if lsp#get_server_status(a:ctx['server_name']) !=# 'running' | return | endif " if server is not running we cant send the request
    " send the actual cancel request
    let a:ctx['dispose'] = lsp#callbag#pipe(
        \ lsp#notification(a:ctx['server_name'], {
        \   'method': '$/cancelRequest',
        \   'params': { 'id': a:ctx['request_id'] },
        \ }),
        \ lsp#callbag#subscribe({
        \   'error':{e->s:send_request_dispose(a:ctx)},
        \   'complete':{->s:send_request_dispose(a:ctx)},
        \ })
        \)
endfunction

function! lsp#send_request(server_name, request) abort
    let l:ctx = {
        \ 'server_name': a:server_name,
        \ 'request': copy(a:request),
        \ 'cb': has_key(a:request, 'on_notification') ? a:request['on_notification'] : function('s:Noop'),
        \ }
    let l:ctx['dispose'] = lsp#callbag#pipe(
        \ lsp#request(a:server_name, a:request),
        \ lsp#callbag#subscribe({
        \   'next':{d->l:ctx['cb'](d)},
        \   'error':{e->s:send_request_error(l:ctx, e)},
        \   'complete':{->s:send_request_dispose(l:ctx)},
        \ })
        \)
endfunction

function! s:send_request_dispose(ctx) abort
    " dispose function may not have been created so check before calling
    if has_key(a:ctx, 'dispose')
        call a:ctx['dispose']()
    endif
endfunction

function! s:send_request_error(ctx, error) abort
    call a:ctx['cb'](a:error)
    call s:send_request_dispose(a:ctx)
endfunction
" }}}

" lsp#notification {{{
function! lsp#notification(server_name, request) abort
    return lsp#callbag#lazy(function('s:send_notification', [a:server_name, a:request]))
endfunction
" }}}

" omnicompletion
function! lsp#complete(...) abort
    return call('lsp#omni#complete', a:000)
endfunction

function! lsp#tagfunc(...) abort
    return call('lsp#tag#tagfunc', a:000)
endfunction

let s:didchange_queue = []
let s:didchange_timer = -1

function! s:add_didchange_queue(buf) abort
    if g:lsp_use_event_queue == 0
        for l:server_name in lsp#get_allowed_servers(a:buf)
            call s:ensure_flush(a:buf, l:server_name, function('s:Noop'))
        endfor
        return
    endif
    if index(s:didchange_queue, a:buf) != -1
        return
    endif
    call add(s:didchange_queue, a:buf)
    call lsp#log('s:send_didchange_queue() will be triggered')
    call timer_stop(s:didchange_timer)
    let l:lazy = &updatetime > 1000 ? &updatetime : 1000
    let s:didchange_timer = timer_start(l:lazy, function('s:send_didchange_queue'))
endfunction

function! s:send_didchange_queue(...) abort
    call lsp#log('s:send_event_queue()')
    for l:buf in s:didchange_queue
        if !bufexists(l:buf)
            continue
        endif
        for l:server_name in lsp#get_allowed_servers(l:buf)
            call s:ensure_flush(l:buf, l:server_name, function('s:Noop'))
        endfor
    endfor
    let s:didchange_queue = []
endfunction

function! lsp#enable_diagnostics_for_buffer(...) abort
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    call lsp#internal#diagnostics#state#_enable_for_buffer(l:bufnr)
endfunction

function! lsp#disable_diagnostics_for_buffer(...) abort
    let l:bufnr = a:0 > 0 ? a:1 : bufnr('%')
    call lsp#internal#diagnostics#state#_disable_for_buffer(l:bufnr)
endfunction

" Return dict with diagnostic counts for current buffer
" { 'error': 1, 'warning': 0, 'information': 0, 'hint': 0 }
function! lsp#get_buffer_diagnostics_counts() abort
    return lsp#internal#diagnostics#state#_get_diagnostics_count_for_buffer(bufnr('%'))
endfunction

" Return first error line or v:null if there are no errors
function! lsp#get_buffer_first_error_line() abort
    return lsp#internal#diagnostics#first_line#get_first_error_line({'bufnr': bufnr('%')})
endfunction

" Return UI list with window/workDoneProgress
" The list is most recently update order.
" [{ 'server': 'clangd', 'token': 'backgroundIndexProgress', 'title': 'indexing', 'messages': '50/100', 'percentage': 50 },
"  { 'server': 'rust-analyzer', 'token': 'rustAnalyzer/indexing', 'title': 'indexing', 'messages': '9/262 (std)', 'percentage': 3 }]
" 'percentage': 0 - 100 or not exist
function! lsp#get_progress() abort
    return lsp#internal#work_done_progress#get_progress()
endfunction

"
" Scroll vim-lsp related windows.
"
" NOTE: This method can be used to <expr> mapping.
"
function! lsp#scroll(count) abort
    let l:ctx = {}
    function! l:ctx.callback(count) abort
        let l:Window = vital#lsp#import('VS.Vim.Window')
        for l:winid in l:Window.find({ winid -> l:Window.is_floating(winid) })
            call l:Window.scroll(l:winid, l:Window.info(l:winid).topline + a:count)
        endfor
    endfunction
    call timer_start(0, { -> l:ctx.callback(a:count) })
    return "\<Ignore>"
endfunction

function! s:merge_dict(dict_old, dict_new) abort
    for l:key in keys(a:dict_new)
        if has_key(a:dict_old, l:key) && type(a:dict_old[l:key]) == v:t_dict && type(a:dict_new[l:key]) == v:t_dict
            call s:merge_dict(a:dict_old[l:key], a:dict_new[l:key])
        else
            let a:dict_old[l:key] = a:dict_new[l:key]
        endif
    endfor
endfunction

function! lsp#update_workspace_config(server_name, workspace_config) abort
    let l:server = s:servers[a:server_name]
    let l:server_info = l:server['server_info']
    if has_key(l:server_info, 'workspace_config')
        call s:merge_dict(l:server_info['workspace_config'], a:workspace_config)
    else
        let l:server_info['workspace_config'] = a:workspace_config
    endif
    let l:server_info['_workspace_config_sent'] = v:false
    call s:ensure_conf(bufnr('%'), a:server_name, function('s:Noop'))
endfunction

function! lsp#server_complete(lead, line, pos) abort
    return filter(sort(keys(s:servers)), 'stridx(v:val, a:lead)==0 && has_key(s:servers[v:val], "init_result")')
endfunction

function! lsp#_new_command() abort
    let s:last_command_id += 1
    call lsp#stream(1, { 'command': 1 })
    return s:last_command_id
endfunction

function! lsp#_last_command() abort
    return s:last_command_id
endfunction
