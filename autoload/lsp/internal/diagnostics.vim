function! lsp#internal#diagnostics#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_diagnostics_enabled | return | endif

    call lsp#internal#diagnostics#state#_enable() " Needs to be the first one to register
    call lsp#internal#diagnostics#echo#_enable()
    call lsp#internal#diagnostics#highlights#_enable()
    call lsp#internal#diagnostics#float#_enable()
    call lsp#internal#diagnostics#signs#_enable()
    call lsp#internal#diagnostics#virtual_text#_enable()
endfunction

function! lsp#internal#diagnostics#_disable() abort
    call lsp#internal#diagnostics#echo#_disable()
    call lsp#internal#diagnostics#float#_disable()
    call lsp#internal#diagnostics#highlights#_disable()
    call lsp#internal#diagnostics#virtual_text#_disable()
    call lsp#internal#diagnostics#signs#_disable()
    call lsp#internal#diagnostics#state#_disable() " Needs to be the last one to unregister
endfunction
