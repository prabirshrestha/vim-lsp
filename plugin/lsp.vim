if exists('g:lsp_loaded')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_hover_balloon_eval = get(g:, 'lsp_hover_balloon_eval', has('balloon_eval'))
let g:lsp_async_completion = get(g:, 'lsp_async_completion', 0)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])

if g:lsp_auto_enable
    au VimEnter * call lsp#enable()
endif

command! LspDefinition call lsp#ui#vim#definition()
command! LspDocumentSymbol call lsp#ui#vim#document_symbol()
command! LspDocumentDiagnostics call lsp#ui#vim#document_diagnostics()
command! LspHover call lsp#ui#vim#hover()
command! LspReferences call lsp#ui#vim#references()
command! LspRename call lsp#ui#vim#rename()
command! LspWorkspaceSymbol call lsp#ui#vim#workspace_symbol()
command! LspDocumentFormat call lsp#ui#vim#document_format()
command! -range LspDocumentRangeFormat call lsp#ui#vim#document_range_format()
