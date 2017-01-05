let s:save_cpo = &cpo
set cpo&vim

let s:lsp_clients = {} " { id, opts, req_seq, on_notifications: { 'req_seq': { request, on_notification } }, stdout: { max_buffer_size, buffer, content_length, headers } }
let s:lsp_default_max_buffer = -1

function! s:trim(str) abort
  return matchstr(a:str,'^\s*\zs.\{-}\ze\s*$')
endfunction

function! s:_on_lsp_stdout(id, data, event) abort
    if has_key(s:lsp_clients, a:id)
        let l:client = s:lsp_clients[a:id]

        let l:client.stdout.buffer .= join(a:data, "\n")

        if l:client.stdout.max_buffer_size != -1 && len(l:client.stdout.buffer) > l:client.stdout.max_buffer_size
            echom 'lsp: reached max buffer size'
            call async#job#stop(a:id)
        endif

        while 1
            if l:client.stdout.content_length == -1         " if content-length is -1 we haven't parsed the headers
                " wait for all the headers to arrive
                let l:header_end_index = stridx(l:client.stdout.buffer, "\r\n\r\n")
                if l:header_end_index >= 0
                    for l:header in split(l:client.stdout.buffer[:l:header_end_index - 1], "\r\n")
                        let l:header_key_value_seperator = stridx(l:header, ":")
                        let l:header_key = s:trim(l:header[:l:header_key_value_seperator - 1])
                        let l:header_value = s:trim(l:header[l:header_key_value_seperator + 1:])
                        if l:header_key ==? 'Content-Length'
                            let l:client.stdout.content_length = str2nr(l:header_value, 10)
                        endif
                        let l:client.stdout.headers[l:header_key] = s:trim(l:header_value)
                    endfor
                    let l:client.stdout.buffer = l:client.stdout.buffer[l:header_end_index + 4:]
                    continue
                else
                    " wait for next buffer to arrive
                    break
                endif
            else
                if len(l:client.stdout.buffer) >= l:client.stdout.content_length
                    " we have the full message
                    let l:response_str = l:client.stdout.buffer[:l:client.stdout.content_length - 1]
                    let l:client.stdout.buffer = l:client.stdout.buffer[l:client.stdout.content_length:]
                    let l:client.stdout.content_length = -1 " reset since we are done reading the current message
                    let l:response_msg = json_decode(l:response_str)
                    if has_key(l:response_msg, 'id')
                        let l:on_notification_data = { 'response': l:response_msg }
                        if has_key(l:client.on_notifications, l:response_msg.id)
                            " requests are absent for server instantiated events
                            let l:on_notification_data.request = l:client.on_notifications[l:response_msg.id].request
                        endif
                        if has_key(l:client.opts, 'on_notification')
                            " call the client's on_notification
                            call l:client.opts.on_notification(a:id, l:on_notification_data, 'on_notification')
                        endif
                        if has_key(l:client.on_notifications, l:response_msg.id) && has_key(l:client.on_notifications[l:response_msg.id], 'on_notification')
                            " call on notification registered during send
                            call l:client.on_notifications[l:response_msg.id].on_notification(a:id, l:on_notification_data, 'on_notification')
                        endif
                        if has_key(l:client.on_notifications, l:response_msg.id)
                            " requests are absent for server instantiated events
                            call remove(l:client.on_notifications, l:response_msg.id)
                        endif
                    endif
                    if len(l:client.stdout.buffer) > 0
                        " we have more data in the buffer so try parsing the new headers from top
                        continue
                    else
                        " we are done processing the message here so stop
                        break
                    endif
                else
                    " we don't have the entire message body, so wait for the next buffer
                    break
                endif
            endif
        endwhile
    endif
endfunction

function! s:_on_lsp_stderr(id, data, event) abort
    if has_key(s:lsp_clients, a:id)
        let l:client = s:lsp_clients[a:id]
        if has_key(l:client.opts, 'on_stderr')
            call l:client.opts.on_stderr(a:id, a:data, a:event)
        endif
    endif
endfunction

function! s:_on_lsp_exit(id, status, event) abort
    if has_key(s:lsp_clients, a:id)
        let l:client = s:lsp_clients[a:id]
        if has_key(l:client.opts, 'on_exit')
            call l:client.opts.on_exit(a:id, a:status, a:event)
        endif
    endif
endfunction

function! s:lsp_start(opts) abort
    if !has_key(a:opts, 'cmd')
        return -1
    endif

    let l:lsp_client_id = async#job#start(a:opts.cmd, {
        \ 'on_stdout': function('s:_on_lsp_stdout'),
        \ 'on_stderr': function('s:_on_lsp_stderr'),
        \ 'on_exit': function('s:_on_lsp_exit'),
    \ })

    if l:lsp_client_id <= 0
        return l:lsp_client_id
    endif

    let l:max_buffer_size = s:lsp_default_max_buffer
    if has_key(a:opts, 'max_buffer_size')
        let l:max_buffer_size = a:opts.max_buffer_size
    endif

    let s:lsp_clients[l:lsp_client_id] = {
        \ 'id': l:lsp_client_id,
        \ 'opts': a:opts,
        \ 'req_seq': 0,
        \ 'on_notifications': {},
        \ 'stdout': {
            \ 'max_buffer_size': l:max_buffer_size,
            \ 'buffer': '',
            \ 'content_length': -1,
            \ 'headers': {}
        \ },
    \ }

    return l:lsp_client_id
endfunction

function! s:lsp_stop(id) abort
    call async#job#stop(a:id)
endfunction

function! s:lsp_send_request(id, opts) abort " opts = { method, params?, on_notification }
    if has_key(s:lsp_clients, a:id)
        let l:client = s:lsp_clients[a:id]

        let l:client.req_seq = l:client.req_seq + 1
        let l:req_seq = l:client.req_seq

        let l:msg = { 'jsonrpc': '2.0', 'id': l:req_seq, 'method': a:opts.method }
        if has_key(a:opts, 'params')
            let l:msg.params = a:opts.params
        endif

        let l:json = json_encode(l:msg)
        let l:req_data = 'Content-Length: ' . len(l:json) . "\r\n\r\n" . l:json

        let l:client.on_notifications[l:req_seq] = { 'request': l:msg }
        if has_key(a:opts, 'on_notification')
            let l:client.on_notifications[l:req_seq].on_notification = a:opts.on_notification
        endif

        call async#job#send(l:client.id, l:req_data)

        return l:req_seq
    else
        return -1
    endif
endfunction

function! s:lsp_get_last_request_id(id) abort
    return s:lsp_clients[a:id].req_seq
endfunction

function! s:lsp_is_error(notification) abort
    return has_key(a:notification, 'error')
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

function! lsp#client#send(client_id, opts) abort
    return s:lsp_send_request(a:client_id, a:opts)
endfunction

function! lsp#client#get_last_request_id(client_id) abort
    return s:lsp_get_last_request_id(a:client_id)
endfunction

function! lsp#client#is_error(notification) abort
    return s:lsp_is_error(a:notification)
endfunction

function! lsp#client#is_server_instantiated_notification(notification)
    return s:is_server_instantiated_notification(a:notification)
endfunction

" }}}

let &cpo = s:save_cpo
unlet s:save_cpo
" vim sw=4 ts=4 et
