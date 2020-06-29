function! lsp#internal#diagnostics#float#_enable() abort
    " don't even bother registering if the feature is disabled
    if !lsp#ui#vim#output#float_supported() | return | endif
    if !g:lsp_diagnostics_float_cursor | return | endif 

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#fromEvent('CursorMoved'),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_float_cursor}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_float_delay),
        \ lsp#callbag#map({_->{'bufnr': bufnr('%'), 'curpos': getcurpos()[0:2], 'changedtick': b:changedtick }}),
        \ lsp#callbag#distinctUntilChanged({a,b -> a['bufnr'] == b['bufnr'] && a['curpos'] == b['curpos'] && a['changedtick'] == b['changedtick']}),
        \ lsp#callbag#filter({_->mode() is# 'n'}),
        \ lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !=# 'terminal' }),
        \ lsp#callbag#map({_->lsp#ui#vim#diagnostics#get_diagnostics_under_cursor()}),
        \ lsp#callbag#subscribe({x->s:show_float(x)}),
        \ )
endfunction

function! lsp#internal#diagnostics#float#_disable() abort
    if exists('s:Dispose') | call s:Dispose() | endif
endfunction

function! s:show_float(diagnostic) abort
    if !empty(a:diagnostic) && has_key(a:diagnostic, 'message')
        let l:lines = split(a:diagnostic['message'], '\n', 1)
        call lsp#ui#vim#output#preview('', l:lines, {
            \   'statusline': ' LSP Diagnostics'
            \})
        let s:displaying_message = 1
    elseif get(s:, 'displaying_message', 0)
        call lsp#ui#vim#output#closepreview()
        let s:displaying_message = 0
    endif
endfunction
