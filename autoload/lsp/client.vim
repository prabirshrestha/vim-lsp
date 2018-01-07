let s:save_cpo = &cpo
set cpo&vim

let s:clients = {} " { client_id: ctx }

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

    if empty(l:ctx['buffer'])
        let l:ctx['buffer'] = join(a:data, "\n")
    else
        let l:ctx['buffer'] .= join(a:data, "\n")
    endif

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
            if has_key(l:response, 'id')
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
                        call lsp#log('s:on_stdout client option on_notification() error', v:exception)
                    endtry
                endif
                if has_key(l:ctx['on_notifications'], l:response['id'])
                    " call lsp#client#send({ 'on_notification }) second
                    try
                        call l:ctx['on_notifications'][l:response['id']](a:id, l:on_notification_data, 'on_notification')
                    catch
                        call lsp#log('s:on_stdout client request on_notification() error', v:exception)
                    endtry
                    unlet l:ctx['on_notifications'][l:response['id']]
                endif
                unlet l:ctx['requests'][l:response['id']]
            else
                " it is a notification
                if has_key(l:ctx['opts'], 'on_notification')
                    try
                        call l:ctx['opts']['on_notification'](a:id, l:on_notification_data, 'on_notification')
                    catch
                        call lsp#log('s:on_stdout on_notification() error', v:exception)
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
            call lsp#log('s:on_stderr exception', v:exception)
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
            call lsp#log('s:on_exit exception', v:exception)
            echom v:exception
        endtry
    endif
    call s:dispose_context(a:id)
endfunction

function! s:lsp_start(opts) abort
    if !has_key(a:opts, 'cmd')
        return -1
    endif

    let l:client_id = async#job#start(a:opts.cmd, {
        \ 'on_stdout': function('s:on_stdout'),
        \ 'on_stderr': function('s:on_stderr'),
        \ 'on_exit': function('s:on_exit'),
        \ })

    let l:ctx = s:create_context(l:client_id, a:opts)
    let l:ctx['id'] = l:client_id

    return l:client_id
endfunction

function! s:lsp_stop(id) abort
    call async#job#stop(a:id)
endfunction

let s:send_type_request = 1
let s:send_type_notification = 2
function! s:lsp_send(id, opts, type) abort " opts = { method, params?, on_notification }
    let l:ctx = get(s:clients, a:id, {})
    if empty(l:ctx)
        return -1
    endif

    let l:request = { 'jsonrpc': '2.0', 'method': a:opts['method'] }

    if (a:type == s:send_type_request)
        let l:ctx['request_sequence'] = l:ctx['request_sequence'] + 1
        let l:request['id'] = l:ctx['request_sequence']
        let l:ctx['requests'][l:request['id']] = l:request
        if has_key(a:opts, 'on_notification')
            let l:ctx['on_notifications'][l:request['id']] = a:opts['on_notification']
        endif
    endif

    if has_key(a:opts, 'params')
        let l:request['params'] = a:opts['params']
    endif

    let l:json = json_encode(l:request)
    let l:payload = 'Content-Length: ' . len(l:json) . "\r\n\r\n" . l:json

    call async#job#send(a:id, l:payload)

    if (a:type == s:send_type_request)
        return l:request['id']
    else
        return 0
    endif
endfunction

function! s:lsp_get_last_request_id(id) abort
    return s:clients[a:id]['request_sequence']
endfunction

function! s:lsp_is_error(obj_or_response) abort
    return has_key(a:obj_or_response, 'error')
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

function! lsp#client#get_last_request_id(client_id) abort
    return s:lsp_get_last_request_id(a:client_id)
endfunction

function! lsp#client#is_error(obj_or_response) abort
    return s:lsp_is_error(a:obj_or_response)
endfunction

function! lsp#client#is_server_instantiated_notification(notification) abort
    return s:is_server_instantiated_notification(a:notification)
endfunction

" }}}

let &cpo = s:save_cpo
unlet s:save_cpo
" vim sw=4 ts=4 et
