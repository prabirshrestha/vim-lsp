" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0

function! lsp#internal#diagnostics#echo#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_echo_cursor | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#fromEvent(['CursorMoved']),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_echo_cursor}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_echo_delay),
        \ lsp#callbag#map({_->{'bufnr': bufnr('%'), 'curpos': getcurpos()[0:2], 'changedtick': b:changedtick }}),
        \ lsp#callbag#distinctUntilChanged({a,b -> a['bufnr'] == b['bufnr'] && a['curpos'] == b['curpos'] && a['changedtick'] == b['changedtick']}),
        \ lsp#callbag#filter({_->mode() is# 'n'}),
        \ lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !=# 'terminal' }),
        \ lsp#callbag#map({_->lsp#internal#diagnostics#under_cursor#get_diagnostic()}),
        \ lsp#callbag#subscribe({x->s:echo(x)}),
        \ )
endfunction

function! lsp#internal#diagnostics#echo#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    let s:enabled = 0
endfunction

function! s:echo(diagnostic) abort
    if !empty(a:diagnostic) && has_key(a:diagnostic, 'message')
        call lsp#utils#echo_with_truncation('LSP: '. substitute(a:diagnostic['message'], '\n\+', ' ', 'g'))
        let s:displaying_message = 1
    elseif get(s:, 'displaying_message', 0)
        call lsp#utils#echo_with_truncation('')
        let s:displaying_message = 0
    endif
endfunction
