if exists('g:lsp_loaded')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_async_completion = get(g:, 'lsp_async_completion', 0)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])
let g:lsp_signs_enabled = get(g:, 'lsp_signs_enabled', 0)
let g:lsp_signs_error = get(g:, 'lsp_signs_error', {})
let g:lsp_signs_warning = get(g:, 'lsp_signs_warning', {})
let g:lsp_signs_information = get(g:, 'lsp_signs_information', {})
let g:lsp_signs_hint = get(g:, 'lsp_signs_hint', {})
let g:lsp_diagnostics_enabled = get(g:, 'lsp_diagnostics_enabled', 1)
let g:lsp_diagnostics_echo_cursor = get(g:, 'lsp_diagnostics_echo_cursor', 0)
let g:lsp_diagnostics_echo_delay = get(g:, 'lsp_diagnostics_echo_delay', 500)
let g:lsp_next_sign_id = get(g:, 'lsp_next_sign_id', 6999)
let g:lsp_preview_keep_focus = get(g:, 'lsp_preview_keep_focus', 1)
let g:lsp_use_event_queue = get(g:, 'lsp_use_event_queue', 0)

if g:lsp_auto_enable
    augroup lsp_auto_enable
        autocmd!
        autocmd VimEnter * call lsp#enable()
    augroup END
endif

command! LspCodeAction call lsp#ui#vim#code_action()
command! LspDeclaration call lsp#ui#vim#declaration()
command! LspDefinition call lsp#ui#vim#definition()
command! LspDocumentSymbol call lsp#ui#vim#document_symbol()
command! LspDocumentDiagnostics call lsp#ui#vim#diagnostics#document_diagnostics()
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspHover call lsp#ui#vim#hover#get_hover_under_cursor()
command! LspNextError call lsp#ui#vim#signs#next_error()
command! LspPreviousError call lsp#ui#vim#signs#previous_error()
command! LspReferences call lsp#ui#vim#references()
command! LspRename call lsp#ui#vim#rename()
command! LspTypeDefinition call lsp#ui#vim#type_definition()
command! LspWorkspaceSymbol call lsp#ui#vim#workspace_symbol()
command! LspDocumentFormat call lsp#ui#vim#document_format()
command! LspDocumentFormatSync call lsp#ui#vim#document_format_sync()
command! -range LspDocumentRangeFormat call lsp#ui#vim#document_range_format()
command! LspImplementation call lsp#ui#vim#implementation()
command! LspTypeDefinition call lsp#ui#vim#type_definition()
command! -nargs=0 LspStatus echo lsp#get_server_status()

nnoremap <expr> <plug>(lsp-code-action) [lsp#ui#vim#code_action(),''][1]
nnoremap <expr> <plug>(lsp-declaration) [lsp#ui#vim#declaration(), ''][1]
nnoremap <expr> <plug>(lsp-definition) [lsp#ui#vim#definition(), ''][1]
nnoremap <expr> <plug>(lsp-document-symbol) [lsp#ui#vim#document_symbol(),''][1]
nnoremap <expr> <plug>(lsp-document-diagnostics) [lsp#ui#vim#diagnostics#document_diagnostics(),''][1]
nnoremap <expr> <plug>(lsp-hover) [lsp#ui#vim#hover#get_hover_under_cursor(),''][1]
nnoremap <expr> <plug>(lsp-next-error) [lsp#ui#vim#signs#next_error(),''][1]
nnoremap <expr> <plug>(lsp-previous-error) [lsp#ui#vim#signs#previous_error(),''][1]
nnoremap <expr> <plug>(lsp-references) [lsp#ui#vim#references(),''][1]
nnoremap <expr> <plug>(lsp-rename) [lsp#ui#vim#rename(),''][1]
nnoremap <expr> <plug>(lsp-type-definition) [lsp#ui#vim#type_definition(),''][1]
nnoremap <expr> <plug>(lsp-workspace-symbol) [lsp#ui#vim#workspace_symbol(),''][1]
nnoremap <expr> <plug>(lsp-document-format) [lsp#ui#vim#document_format(),''][1]
vnoremap <expr> <plug>(lsp-document-format) [lsp#ui#vim#document_range_format(),''][1]
nnoremap <expr> <plug>(lsp-implementation) [lsp#ui#vim#implementation(),''][1]
nnoremap <expr> <plug>(lsp-status) [execute("echo lsp#get_server_status()",1),''][1]
