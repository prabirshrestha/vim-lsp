if exists('g:lsp_loaded')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')

if g:lsp_auto_enable
    au VimEnter * call lsp#enable()
endif
