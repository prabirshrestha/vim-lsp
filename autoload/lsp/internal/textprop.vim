" TODO: currently, quickpick is generated via vim-quickpick, 'quickpick' is
" not used.
let s:priorities = {
\ 'quickpick': 1,
\ 'folding': 2,
\ 'semantic': 3,
\ 'diagnostics_highlight': 4,
\ 'document_highlight': 5,
\}

function! lsp#internal#textprop#priority(name) abort
    return get(s:priorities, a:name, 0)
endfunction
