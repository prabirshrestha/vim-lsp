function! lsp#ui#vim#diagnostics#float#cursor_moved() abort
    call s:stop_cursor_moved_timer()

    let l:current_pos = getcurpos()[0:2]

    " use timer to avoid recalculation
    if !exists('s:last_pos') || l:current_pos != s:last_pos
        let s:last_pos = l:current_pos
        let s:cursor_moved_timer = timer_start(g:lsp_diagnostics_float_delay, function('s:float_diagnostics_under_cursor'))
    endif
endfunction

function! s:float_diagnostics_under_cursor(...) abort
    let l:diagnostic = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()
    if !empty(l:diagnostic) && has_key(l:diagnostic, 'message')
        let l:lines = split(l:diagnostic['message'], '\n', 1)
        call lsp#ui#vim#output#preview('', l:lines, {
            \   'statusline': ' LSP Diagnostics'
            \})
        let s:displaying_message = 1
    elseif get(s:, 'displaying_message', 0)
        call lsp#ui#vim#output#closepreview()
        let s:displaying_message = 0
    endif
endfunction

function! s:stop_cursor_moved_timer() abort
    if exists('s:cursor_moved_timer')
        call timer_stop(s:cursor_moved_timer)
        unlet s:cursor_moved_timer
    endif
endfunction
