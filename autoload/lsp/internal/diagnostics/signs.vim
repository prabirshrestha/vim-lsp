let s:enabled = 0

function! lsp#internal#diagnostics#signs#_enable() abort
    " don't even bother registering if the feature is disabled
    if !lsp#utils#_has_signs() | return | endif
    if !g:lsp_diagnostics_signs_enabled | return | endif 

    if s:enabled | return | endif
    let s:enabled = 1
endfunction

function! lsp#internal#diagnostics#signs#_disable() abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    let s:enabled = 0
endfunction
