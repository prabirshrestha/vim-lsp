let s:save_cpo = &cpoptions
set cpoptions&vim

let s:clients = {} " { client_id: ctx }

" Vars used by native lsp
let s:jobidseq = 0

function! s:create_context(client_id, opts) abort
    if a:client_id <= 0
        return {}
    endif

    let l:ctx = {
        \ 'opts': a:opts,
        \ 'buffer': '',
        \ 'content-length': -1,
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

    if empty(l:ctx)
        return
    endif

    let l:ctx['buffer'] .= a:data

    while 1
        if l:ctx['content-length'] < 0
            " wait for all headers to arrive
            let l:header_end_index = stridx(l:ctx['buffer'], "\r\n\r\n")
            if l:header_end_index < 0
                " no headers found
                return
            endif
            let l:headers = l:ctx['buffer'][:l:header_end_index - 1]
            let l:ctx['content-length'] = s:get_content_length(l:headers)
            if l:ctx['content-length'] < 0
                " invalid content-length
                call lsp#log('on_stdout', a:id, 'invalid content-length')
                call s:lsp_stop(a:id)
                return
            endif
            let l:ctx['buffer'] = l:ctx['buffer'][l:header_end_index + 4:] " 4 = len(\r\n\r\n)
        endif

        if len(l:ctx['buffer']) < l:ctx['content-length']
            " incomplete message, wait for next buffer to arrive
            return
        endif

        " we have full message
        let l:response_str = l:ctx['buffer'][:l:ctx['content-length'] - 1]
        let l:ctx['content-length'] = -1

        try
            let l:response = json_decode(l:response_str)
        catch
            call lsp#log('s:on_stdout json_decode failed', v:exception)
        endtry

        let l:ctx['buffer'] = l:ctx['buffer'][len(l:response_str):]

        if exists('l:response')
            " call appropriate callbacks
            let l:on_notification_data = { 'response': l:response }
            if has_key(l:response, 'method') && has_key(l:response, 'id')
                " it is a request from a server
                let l:request = l:response
                if has_key(l:ctx['opts'], 'on_request')
                    call l:ctx['opts']['on_request'](a:id, l:request)
                endif
            elseif has_key(l:response, 'id')
                " it is a request->response
                if !(type(l:response['id']) == type(0) || type(l:response['id']) == type(''))
                    " response['id'] can be number | string | null based on the spec
                    call lsp#log('invalid response id. ignoring message', l:response)
                    continue
                endif
                if has_key(l:ctx['requests'], l:response['id'])
                    let l:on_notification_data['request'] = l:ctx['requests'][l:response['id']]
                endif
                if has_key(l:ctx['opts'], 'on_notification')
                    " call client's on_notification first
                    try
                        call l:ctx['opts']['on_notification'](a:id, l:on_notification_data, 'on_notification')
                    catch
                        call lsp#log('s:on_stdout client option on_notification() error', v:exception, v:throwpoint)
                    endtry
                endif
                if has_key(l:ctx['on_notifications'], l:response['id'])
                    " call lsp#client#send({ 'on_notification }) second
                    try
                        call l:ctx['on_notifications'][l:response['id']](a:id, l:on_notification_data, 'on_notification')
                    catch
                        call lsp#log('s:on_stdout client request on_notification() error', v:exception, v:throwpoint)
                    endtry
                    unlet l:ctx['on_notifications'][l:response['id']]
                endif
                if has_key(l:ctx['requests'], l:response['id'])
                    unlet l:ctx['requests'][l:response['id']]
                else
                    call lsp#log('cannot find the request corresponding to response: ', l:response)
                endif
            else
                " it is a notification
                if has_key(l:ctx['opts'], 'on_notification')
                    try
                        call l:ctx['opts']['on_notification'](a:id, l:on_notification_data, 'on_notification')
                    catch
                        call lsp#log('s:on_stdout on_notification() error', v:exception, v:throwpoint)
                    endtry
                endif
            endif
        endif

        if empty(l:response_str)
            " buffer is empty, wait for next message to arrive
            return
        endif
    endwhile
endfunction

function! s:get_content_length(headers) abort
    for l:header in split(a:headers, "\r\n")
        let l:kvp = split(l:header, ':')
        if len(l:kvp) == 2
            if l:kvp[0] =~? '^Content-Length'
                return str2nr(l:kvp[1], 10)
            endif
        endif
    endfor
    return -1
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
    let l:opts = {
        \ 'on_stdout': function('s:on_stdout'),
        \ 'on_stderr': function('s:on_stderr'),
        \ 'on_exit': function('s:on_exit'),
        \ 'normalize': 'string'
        \ }
    if has_key(a:opts, 'env')
        let l:opts.env = a:opts.env
    endif

    if has_key(a:opts, 'cmd')
        let l:client_id = lsp#utils#job#start(a:opts.cmd, l:opts)
    elseif has_key(a:opts, 'tcp')
        let l:client_id = lsp#utils#job#connect(a:opts.tcp, l:opts)
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
    if empty(l:ctx) | return -1 | endif

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

function! s:native_out_cb(cbctx, channel, response) abort
    if !has_key(a:cbctx, 'ctx') | return | endif
    let l:ctx = a:cbctx['ctx']
    if has_key(a:response, 'method') && has_key(a:response, 'id')
        " it is a request from a server
        let l:request = a:response
        if has_key(l:ctx['opts'], 'on_request')
            call l:ctx['opts']['on_request'](l:ctx['id'], l:request)
        endif
    elseif !has_key(a:response, 'id') && has_key(l:ctx['opts'], 'on_notification')
        " it is a notification
        let l:on_notification_data = { 'response': a:response }
        try
            call l:ctx['opts']['on_notification'](l:ctx['id'], l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:native_notification_callback on_notification() error', v:exception, v:throwpoint)
        endtry
    endif
endfunction

function! s:native_err_cb(cbctx, channel, response) abort
    if !has_key(a:cbctx, 'ctx') | return | endif
    let l:ctx = a:cbctx['ctx']
    if has_key(l:ctx['opts'], 'on_stderr')
        try
            call l:ctx['opts']['on_stderr'](l:ctx['id'], a:response, 'stderr')
        catch
            call lsp#log('s:on_stderr exception', v:exception, v:throwpoint)
            echom v:exception
        endtry
    endif
endfunction

" public apis {{{

function! lsp#client#start(opts) abort
    if g:lsp_use_native_client && lsp#utils#has_native_lsp_client()
        if has_key(a:opts, 'cmd')
            let l:cbctx = {}
            let l:jobopt = { 'in_mode': 'lsp', 'out_mode': 'lsp', 'noblock': 1,
                \ 'out_cb': function('s:native_out_cb', [l:cbctx]),
                \ 'err_cb': function('s:native_err_cb', [l:cbctx]),
                \ }
            if has_key(a:opts, 'cwd') | let l:jobopt['cwd'] = a:opts['cwd'] | endif
            if has_key(a:opts, 'env') | let l:jobopt['env'] = a:opts['env'] | endif
            let s:jobidseq += 1
            let l:jobid = s:jobidseq " jobid == clientid
            call lsp#log_verbose('using native lsp client')
            let l:job = job_start(a:opts['cmd'], l:jobopt)
            if job_status(l:job) !=? 'run' | return -1 | endif
            let l:ctx = s:create_context(l:jobid, a:opts)
            let l:ctx['id'] = l:jobid
            let l:ctx['job'] = l:job
            let l:ctx['channel'] = job_getchannel(l:job)
            let l:cbctx['ctx'] = l:ctx
            return l:jobid
        elseif has_key(a:opts, 'tcp')
            " add support for tcp
            call lsp#log('tcp not supported when using native lsp client')
            return -1
        endif
    endif
    return s:lsp_start(a:opts)
endfunction

function! lsp#client#stop(client_id) abort
    if g:lsp_use_native_client && lsp#utils#has_native_lsp_client()
       let l:ctx = get(s:clients, a:client_id, {})
       if empty(l:ctx) | return | endif
       call job_stop(l:ctx['job'])
    else
        return s:lsp_stop(a:client_id)
    endif
endfunction

function! lsp#client#send_request(client_id, opts) abort
    if g:lsp_use_native_client && lsp#utils#has_native_lsp_client()
        let l:ctx = get(s:clients, a:client_id, {})
        if empty(l:ctx) | return -1 | endif
        let l:request = {}
        " id shouldn't be passed to request as vim will overwrite it. refer to :h language-server-protocol
        if has_key(a:opts, 'method') | let l:request['method'] = a:opts['method'] | endif
        if has_key(a:opts, 'params') | let l:request['params'] = a:opts['params'] | endif

        call ch_sendexpr(l:ctx['channel'], l:request, { 'callback': function('s:on_response_native', [l:ctx, l:request]) })
        let l:ctx['requests'][l:request['id']] = l:request
        if has_key(a:opts, 'on_notification')
            let l:ctx['on_notifications'][l:request['id']] = a:opts['on_notification']
        endif
        let l:ctx['request_sequence'] = l:request['id']
        return l:request['id']
    else
        return s:lsp_send(a:client_id, a:opts, s:send_type_request)
    endif
endfunction

function! s:on_response_native(ctx, request, channel, response) abort
    " request -> response
    let l:on_notification_data = { 'response': a:response, 'request': a:request }
    if has_key(a:ctx['opts'], 'on_notification')
        " call client's on_notification first
        try
            call a:ctx['opts']['on_notification'](a:ctx['id'], l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:on_response_native client option on_notification() error', v:exception, v:throwpoint)
        endtry
    endif
    if has_key(a:ctx['on_notifications'], a:request['id'])
        " call lsp#client#send({ 'on_notification' }) second
        try
            call a:ctx['on_notifications'][a:request['id']](a:ctx['id'], l:on_notification_data, 'on_notification')
        catch
            call lsp#log('s:on_response_native client request on_notification() error', v:exception, v:throwpoint, a:request, a:response)
        endtry
        unlet a:ctx['on_notifications'][a:response['id']]
        if has_key(a:ctx['requests'], a:response['id'])
            unlet a:ctx['requests'][a:response['id']]
        else
            call lsp#log('cannot find the request corresponding to response: ', a:response)
        endif
    endif
endfunction

function! lsp#client#send_notification(client_id, opts) abort
    if g:lsp_use_native_client && lsp#utils#has_native_lsp_client()
        let l:ctx = get(s:clients, a:client_id, {})
        if empty(l:ctx) | return -1 | endif
        let l:request = {}
        if has_key(a:opts, 'method') | let l:request['method'] = a:opts['method'] | endif
        if has_key(a:opts, 'params') | let l:request['params'] = a:opts['params'] | endif
        call ch_sendexpr(l:ctx['channel'], l:request)
        return 0
    else
        return s:lsp_send(a:client_id, a:opts, s:send_type_notification)
    endif
endfunction

function! lsp#client#send_response(client_id, opts) abort
    if g:lsp_use_native_client && lsp#utils#has_native_lsp_client()
        let l:ctx = get(s:clients, a:client_id, {})
        if empty(l:ctx) | return -1 | endif
        let l:request = {}
        if has_key(a:opts, 'id') | let l:request['id'] = a:opts['id'] | endif
        if has_key(a:opts, 'result') | let l:request['result'] = a:opts['result'] | endif
        if has_key(a:opts, 'error') | let l:request['error'] = a:opts['error'] | endif
        call ch_sendexpr(l:ctx['channel'], l:request)
        return 0
    else
        return s:lsp_send(a:client_id, a:opts, s:send_type_response)
    endif
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
