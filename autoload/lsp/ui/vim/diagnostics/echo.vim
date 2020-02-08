function! lsp#ui#vim#diagnostics#echo#cursor_moved() abort
    if mode() isnot# 'n'
        " dont' show echo only in normal mode
        return
    endif

    call s:stop_cursor_moved_timer()

    let l:current_pos = getcurpos()[0:2]

    " use timer to avoid recalculation
    if !exists('s:last_pos') || l:current_pos != s:last_pos
        let s:last_pos = l:current_pos
        let s:cursor_moved_timer = timer_start(g:lsp_diagnostics_echo_delay, function('s:echo_diagnostics_under_cursor'))
    endif
endfunction

function! s:echo_diagnostics_under_cursor(...) abort
    let l:diagnostic = lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()
    if !empty(l:diagnostic) && has_key(l:diagnostic, 'message')
        call lsp#utils#echo_with_truncation('LSP: '. substitute(l:diagnostic['message'], '\n\+', ' ', 'g'))
        let s:displaying_message = 1
    elseif get(s:, 'displaying_message', 0)
        call lsp#utils#echo_with_truncation('')
        let s:displaying_message = 0
    endif
endfunction

function! s:stop_cursor_moved_timer() abort
    if exists('s:cursor_moved_timer')
        call timer_stop(s:cursor_moved_timer)
        unlet s:cursor_moved_timer
    endif
endfunction
