let s:save_cpo = &cpoptions
set cpoptions&vim

let s:clients = {} " { client_id: ctx }

function! s:create_context(client_id, opts) abort
    if a:client_id <= 0
        return {}
    endif

    let l:ctx = {
        \ 'opts': a:opts,
        \ 'content-length': -1,
        \ 'current-content-length': 0,
        \ 'headers': [],
        \ 'contents': [],
        \ 'requests': {},
        \ 'request_sequence': 0,
        \ 'on_notifications': {},
        \ }

    let s:clients[a:client_id] = l:ctx

    return l:ctx
endfunction

function! s:dispose_context(client_id) abort
    if a:client_id > 0
        if has_key(s:clients, a:client_id)
            unlet s:clients[a:client_id]
        endif
    endif
endfunction

function! s:on_stdout(id, data, event) abort
    let l:ctx = get(s:clients, a:id, {})
    if empty(l:ctx) | return | endif

    if l:ctx['content-length'] ==# -1
        if !s:on_header(l:ctx, a:data)
            return
        endif
    else
        call add(l:ctx['contents'], a:data)
        let l:ctx['current-content-length'] += strlen(a:data)
        if l:ctx['current-content-length'] < l:ctx['content-length']
            return
        endif
    endif

    let l:buffer = join(l:ctx['contents'], '')
    let l:content = strpart(l:buffer, 0, l:ctx['content-length'])
    let l:remain = strpart(l:buffer, l:ctx['content-length'])

    try
        call s:on_message(a:id, l:ctx, json_decode(l:content))
    catch /.*/
        echomsg string({ 'exception': v:exception, 'throwpoint': v:throwpoint })
    endtry

    let l:ctx['headers'] = []
    let l:ctx['contents'] = []
    let l:ctx['content-length'] = -1
    let l:ctx['current-content-length'] = 0
    if l:remain !=# ''
        " NOTE: criticial to be on next tick for perf
        call timer_start(0, {->s:on_stdout(a:id, l:remain, a:event)})
    endif
endfunction

function! s:on_header(ctx, data) abort
    let l:header_offset = stridx(a:data, "\r\n\r\n") + 4
    if l:header_offset < 4
        call add(a:ctx['headers'], a:data)
        return v:false
    elseif l:header_offset == strlen(a:data)
        call add(a:ctx['headers'], a:data)
    else
        call add(a:ctx['headers'], strpart(a:data, 0, l:header_offset))
        call add(a:ctx['contents'], strpart(a:data, l:header_offset))
        let a:ctx['current-content-length'] += strlen(a:ctx['contents'][-1])
    endif
    let a:ctx['content-length'] = str2nr(get(matchlist(join(a:ctx['headers'], ''), '\ccontent-length:\s*\(\d\+\)'), 1, '-1'))
    return a:ctx['current-content-length'] >= a:ctx['content-length']
endfunction

function! s:on_message(clientid, ctx, message) abort
    if !has_key(a:message, 'id') && has_key(a:message, 'method')
        call s:handle_notification(a:clientid, a:ctx, a:message)
    elseif has_key(a:message, 'id') && has_key(a:message, 'method')
        call s:handle_request(a:clientid, a:ctx, a:message)
    elseif has_key(a:message, 'id')
        call s:handle_response(a:clientid, a:ctx, a:message)
    endif
endfunction

function! s:handle_notification(clientid, ctx, message) abort
    " it is a notification
    let l:on_notification_data = { 'response': a:message }
    if has_key(a:ctx['opts'], 'on_notification')
        try
            call a:ctx['opts']['on_notification'](a:clientid, l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:on_stdout on_notification() error', v:exception, v:throwpoint, a:message)
        endtry
    endif
endfunction

function! s:handle_request(clientid, ctx, message) abort
    if has_key(a:ctx['opts'], 'on_request')
        call a:ctx['opts']['on_request'](a:clientid, a:message)
    endif
endfunction

function! s:handle_response(clientid, ctx, message) abort
    let l:response = a:message
    let l:on_notification_data = { 'response': l:response }
    if has_key(a:ctx['requests'], l:response['id'])
        let l:on_notification_data['request'] = a:ctx['requests'][l:response['id']]
    endif
    if has_key(a:ctx['opts'], 'on_notification')
        " call client's on_notification first
        try
            call a:ctx['opts']['on_notification'](a:clientid, l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:handle_response client option on_notification() error', v:exception, v:throwpoint)
        endtry
    endif
    if has_key(a:ctx['on_notifications'], l:response['id'])
        " call lsp#client#send({ 'on_notification }) second
        try
            call a:ctx['on_notifications'][l:response['id']](a:clientid, l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:handle_response client request on_notification() error', v:exception, v:throwpoint, a:message, l:on_notification_data)
        endtry
        unlet a:ctx['on_notifications'][l:response['id']]
    endif
    if has_key(a:ctx['requests'], l:response['id'])
        unlet a:ctx['requests'][l:response['id']]
    else
        call lsp#log('cannot find the request corresponding to response: ', l:response)
    endif
endfunction

function! s:on_stderr(id, data, event) abort
    let l:ctx = get(s:clients, a:id, {})
    if empty(l:ctx)
        return
    endif
    if has_key(l:ctx['opts'], 'on_stderr')
        try
            call l:ctx['opts']['on_stderr'](a:id, a:data, a:event)
        catch
            call lsp#log('s:on_stderr exception', v:exception, v:throwpoint)
            echom v:exception
        endtry
    endif
endfunction

function! s:on_exit(id, status, event) abort
    let l:ctx = get(s:clients, a:id, {})
    if empty(l:ctx)
        return
    endif
    if has_key(l:ctx['opts'], 'on_exit')
        try
            call l:ctx['opts']['on_exit'](a:id, a:status, a:event)
        catch
            call lsp#log('s:on_exit exception', v:exception, v:throwpoint)
            echom v:exception
        endtry
    endif
    call s:dispose_context(a:id)
endfunction

function! s:lsp_start(opts) abort
    if has_key(a:opts, 'cmd')
        let l:client_id = lsp#utils#job#start(a:opts.cmd, {
            \ 'on_stdout': {id, data, event->s:on_stdout(id, join(data, "\n"), event)},
            \ 'on_stderr': function('s:on_stderr'),
            \ 'on_exit': function('s:on_exit'),
            \ })
    elseif has_key(a:opts, 'tcp')
        let l:client_id = lsp#utils#job#connect(a:opts.tcp, {
            \ 'on_stdout': {id, data, event->s:on_stdout(id, join(data, "\n"), event)},
            \ 'on_stderr': function('s:on_stderr'),
            \ 'on_exit': function('s:on_exit'),
            \ })
    else
        return -1
    endif

    let l:ctx = s:create_context(l:client_id, a:opts)
    let l:ctx['id'] = l:client_id

    return l:client_id
endfunction

function! s:lsp_stop(id) abort
    call lsp#utils#job#stop(a:id)
endfunction

let s:send_type_request = 1
let s:send_type_notification = 2
let s:send_type_response = 3
function! s:lsp_send(id, opts, type) abort " opts = { id?, method?, result?, params?, on_notification }
    let l:ctx = get(s:clients, a:id, {})
    if empty(l:ctx)
        return -1
    endif

    let l:request = { 'jsonrpc': '2.0' }

    if (a:type == s:send_type_request)
        let l:ctx['request_sequence'] = l:ctx['request_sequence'] + 1
        let l:request['id'] = l:ctx['request_sequence']
        let l:ctx['requests'][l:request['id']] = l:request
        if has_key(a:opts, 'on_notification')
            let l:ctx['on_notifications'][l:request['id']] = a:opts['on_notification']
        endif
    endif

    if has_key(a:opts, 'id')
        let l:request['id'] = a:opts['id']
    endif
    if has_key(a:opts, 'method')
        let l:request['method'] = a:opts['method']
    endif
    if has_key(a:opts, 'params')
        let l:request['params'] = a:opts['params']
    endif
    if has_key(a:opts, 'result')
        let l:request['result'] = a:opts['result']
    endif
    if has_key(a:opts, 'error')
        let l:request['error'] = a:opts['error']
    endif

    let l:json = json_encode(l:request)
    let l:payload = 'Content-Length: ' . len(l:json) . "\r\n\r\n" . l:json

    call lsp#utils#job#send(a:id, l:payload)

    if (a:type == s:send_type_request)
        let l:id = l:request['id']
        if get(a:opts, 'sync', 0) !=# 0
            let l:timeout = get(a:opts, 'sync_timeout', -1)
            if lsp#utils#_wait(l:timeout, {-> !has_key(l:ctx['requests'], l:request['id'])}, 1) == -1
                throw 'lsp#client: timeout'
            endif
        endif
        return l:id
    else
        return 0
    endif
endfunction

function! s:lsp_get_last_request_id(id) abort
    return s:clients[a:id]['request_sequence']
endfunction

function! s:lsp_is_error(obj_or_response) abort
    let l:vt = type(a:obj_or_response)
    if l:vt == type('')
        return len(a:obj_or_response) > 0
    elseif l:vt == type({})
        return has_key(a:obj_or_response, 'error')
    endif
    return 0
endfunction


function! s:is_server_instantiated_notification(notification) abort
    return !has_key(a:notification, 'request')
endfunction

" public apis {{{

function! lsp#client#start(opts) abort
    return s:lsp_start(a:opts)
endfunction

function! lsp#client#stop(client_id) abort
    return s:lsp_stop(a:client_id)
endfunction

function! lsp#client#send_request(client_id, opts) abort
    return s:lsp_send(a:client_id, a:opts, s:send_type_request)
endfunction

function! lsp#client#send_notification(client_id, opts) abort
    return s:lsp_send(a:client_id, a:opts, s:send_type_notification)
endfunction

function! lsp#client#send_response(client_id, opts) abort
    return s:lsp_send(a:client_id, a:opts, s:send_type_response)
endfunction

function! lsp#client#get_last_request_id(client_id) abort
    return s:lsp_get_last_request_id(a:client_id)
endfunction

function! lsp#client#is_error(obj_or_response) abort
    return s:lsp_is_error(a:obj_or_response)
endfunction

function! lsp#client#error_message(obj_or_response) abort
    try
        return a:obj_or_response['error']['data']['message']
    catch
    endtry
    try
        return a:obj_or_response['error']['message']
    catch
    endtry
    return string(a:obj_or_response)
endfunction

function! lsp#client#is_server_instantiated_notification(notification) abort
    return s:is_server_instantiated_notification(a:notification)
endfunction

" }}}

let &cpoptions = s:save_cpo
unlet s:save_cpo
" vim sw=4 ts=4 et
