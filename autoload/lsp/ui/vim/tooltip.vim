" Generic functions for interacting with tooltip-type windows for hover,
" preview etc.

if !has('nvim') && has('patch-8.1.1517') && g:lsp_preview_float 
    let s:create_tooltip = function('lsp#ui#vim#tooltip#popup#create_tooltip')
elseif has('nvim') && exists('*nvim_open_win') && g:lsp_preview_float 
    let s:create_tooltip = function('lsp#ui#vim#tooltip#float#create_tooltip')
else
    let s:create_tooltip = function('lsp#ui#vim#tooltip#preview#screate_tooltip')
endif

function! lsp#ui#vim#tooltip#show_cursor_tooltip(lines, filetype, synranges, options) abort
    " ...
    let winid = s:create_tooltip()
    " ...
endfunction
