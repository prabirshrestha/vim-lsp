" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
let s:enabled = 0

function! lsp#internal#completion#documentation#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_documentation_float | return | endif

    if !exits('##CompleteChanged') | return | endif

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#fromEvent(['CompleteChanged'], 'vim_lsp_complete_changed_documentation'),
        \ lsp#callbag#filter({_->g:lsp_documentation_float}),
        \ lsp#callbag#debounceTime(250),
        \ )

    if s:enabled | return | endif
    let s:enabled = 1
endfunction

function! lsp#internal#completion#documentation#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction
