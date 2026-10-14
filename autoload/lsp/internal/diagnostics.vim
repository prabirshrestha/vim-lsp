function! lsp#internal#diagnostics#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_enabled | return | endif

    call lsp#internal#diagnostics#state#_enable() " Needs to be the first one to register
    if g:lsp_diagnostics_echo_cursor
        call lsp#internal#diagnostics#echo#_enable()
    endif
    call lsp#internal#diagnostics#highlights#_enable()
    call lsp#internal#diagnostics#float#_enable()
    call lsp#internal#diagnostics#signs#_enable()
    if g:lsp_diagnostics_virtual_text_enabled
        call lsp#internal#diagnostics#virtual_text#_enable()
    endif
endfunction

function! lsp#internal#diagnostics#_disable() abort
    if exists('*lsp#internal#diagnostics#echo#_disable')
        call lsp#internal#diagnostics#echo#_disable()
    endif
    call lsp#internal#diagnostics#float#_disable()
    call lsp#internal#diagnostics#highlights#_disable()
    if exists('*lsp#internal#diagnostics#virtual_text#_disable')
        call lsp#internal#diagnostics#virtual_text#_disable()
    endif
    call lsp#internal#diagnostics#signs#_disable()
    call lsp#internal#diagnostics#state#_disable() " Needs to be the last one to unregister
endfunction
