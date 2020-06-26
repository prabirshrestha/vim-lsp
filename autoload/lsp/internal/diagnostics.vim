function! lsp#internal#diagnostics#_enable() abort
    call lsp#internal#diagnostics#echo#_enable()
    call lsp#internal#diagnostics#float#_enable()
endfunction

function! lsp#internal#diagnostics#_disable() abort
    call lsp#internal#diagnostics#echo#_disable()
    call lsp#internal#diagnostics#float#_disable()
endfunction
