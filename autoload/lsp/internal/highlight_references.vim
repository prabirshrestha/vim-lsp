function! lsp#internal#highlight_references#_enable() abort
    " don't event bother registering if the feature is disabled
    if !g:lsp_highlight_references_enabled | return | endif
endfunction

function! lsp#internal#highlight_references#_enable() abort
    if exists('s:Dispose') | call s:Dispose() | endif
endfunction
