if exists('g:lsp_loaded')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])

if g:lsp_auto_enable
    au VimEnter * call lsp#enable()
endif

command! LspGetWorkspaceSymbols call lsp#ui#vim#get_workspace_symbols()
command! LspGetDocumentSymbols call lsp#ui#vim#get_document_symbols()
command! LspDefinition call lsp#ui#vim#definition()
command! LspReferences call lsp#ui#vim#references()
