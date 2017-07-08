function! s:next(steps, current_index, result) abort
    if len(a:steps) == a:current_index
        return
    endif
    let l:Step = a:steps[a:current_index]
    let l:ctx = {
        \ 'callback': function('s:callback', [a:steps, a:current_index]),
        \ 'result': a:result
        \ }
    call call(l:Step, [l:ctx])
endfunction

function! s:callback(steps, current_index, ...) abort
    call s:next(a:steps, a:current_index + 1, a:000)
endfunction

function! lsp#utils#step#start(steps) abort
    call s:next(a:steps, 0, [])
endfunction
