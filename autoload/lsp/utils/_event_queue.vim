let s:event_queue = []
let s:event_timer = -1

function! lsp#utils#_event_queue#add(queue) abort
    for l:queue in s:event_queue
        if l:queue[0] == a:queue[0] && l:queue[1] == a:queue[1]
            return
        endif
    endfor
    call add(s:event_queue, a:queue)
    call lsp#log('s:send_event_queue() will be triggered')
    call timer_stop(s:event_timer)
    let lazy = &updatetime > 1000 ? &updatetime : 1000
    let s:event_timer = timer_start(lazy, function('s:send_event_queue'))
endfunction

function! s:send_event_queue(timer) abort
    call lsp#log('s:send_event_queue()')
    for l:queue in s:event_queue
        for l:server_name in lsp#get_whitelisted_servers()
            call s:ensure_flush(l:queue[0], l:server_name, l:queue[1])
        endfor
    endfor
    let s:event_queue = []
endfunction


