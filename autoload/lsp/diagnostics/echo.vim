function! lsp#diagnostics#echo#_setup() abort
    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#fromEvent('CursorMoved'),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_echo_cursor}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_echo_delay),
        \ lsp#callbag#filter({_->mode() is# 'n'}),
        \ lsp#callbag#map({_->{'bufnr': bufnr('%'), 'curpos': getcurpos()[0:2] }}),
        \ lsp#callbag#distinctUntilChanged({a,b -> a['bufnr'] == b['bufnr'] && a['curpos'] == b['curpos']}),
        \ lsp#callbag#map({_->lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()}),
        \ lsp#callbag#subscribe({x->s:echo(x)}),
        \ )
endfunction

function! lsp#diagnostics#echo#_uninstall() abort
    if exists('s:Dispose') | call s:Dispose() | endif
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
