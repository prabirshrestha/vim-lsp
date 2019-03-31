if exists('g:lsp_loaded') || !exists('*json_encode') || !has('timers') || !has('lambda')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_async_completion = get(g:, 'lsp_async_completion', 0)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])
let g:lsp_signs_enabled = get(g:, 'lsp_signs_enabled', has('patch-8.1.0772') && exists('*sign_define'))
let g:lsp_virtual_text_enabled = get(g:, 'lsp_virtual_text_enabled', exists('*nvim_buf_set_virtual_text'))
let g:lsp_highlights_enabled = get(g:, 'lsp_highlights_enabled', exists('*nvim_buf_add_highlight'))
let g:lsp_signs_error = get(g:, 'lsp_signs_error', {})
let g:lsp_signs_warning = get(g:, 'lsp_signs_warning', {})
let g:lsp_signs_information = get(g:, 'lsp_signs_information', {})
let g:lsp_signs_hint = get(g:, 'lsp_signs_hint', {})
let g:lsp_diagnostics_enabled = get(g:, 'lsp_diagnostics_enabled', 1)
let g:lsp_diagnostics_echo_cursor = get(g:, 'lsp_diagnostics_echo_cursor', 0)
let g:lsp_diagnostics_echo_delay = get(g:, 'lsp_diagnostics_echo_delay', 500)
let g:lsp_next_sign_id = get(g:, 'lsp_next_sign_id', 6999)
let g:lsp_preview_keep_focus = get(g:, 'lsp_preview_keep_focus', 1)
let g:lsp_use_event_queue = get(g:, 'lsp_use_event_queue', has('nvim') || has('patch-8.1.0889'))
let g:lsp_insert_text_enabled= get(g:, 'lsp_insert_text_enabled', 1)
let g:lsp_text_edit_enabled = get(g:, 'lsp_text_edit_enabled', has('patch-8.0.1493'))

if g:lsp_auto_enable
    augroup lsp_auto_enable
        autocmd!
        autocmd VimEnter * call lsp#enable()
    augroup END
endif

command! -range LspCodeAction call lsp#ui#vim#code_action()
command! LspDeclaration call lsp#ui#vim#declaration()
command! LspDefinition call lsp#ui#vim#definition()
command! LspDocumentSymbol call lsp#ui#vim#document_symbol()
command! LspDocumentDiagnostics call lsp#ui#vim#diagnostics#document_diagnostics()
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspHover call lsp#ui#vim#hover#get_hover_under_cursor()
command! LspNextError call lsp#ui#vim#diagnostics#next_error()
command! LspPreviousError call lsp#ui#vim#diagnostics#previous_error()
command! LspReferences call lsp#ui#vim#references()
command! LspRename call lsp#ui#vim#rename()
command! LspTypeDefinition call lsp#ui#vim#type_definition()
command! LspWorkspaceSymbol call lsp#ui#vim#workspace_symbol()
command! -range LspDocumentFormat call lsp#ui#vim#document_format()
command! -range LspDocumentFormatSync call lsp#ui#vim#document_format_sync()
command! -range LspDocumentRangeFormat call lsp#ui#vim#document_range_format()
command! -range LspDocumentRangeFormatSync call lsp#ui#vim#document_range_format_sync()
command! LspImplementation call lsp#ui#vim#implementation()
command! LspTypeDefinition call lsp#ui#vim#type_definition()
command! -nargs=0 LspStatus echo lsp#get_server_status()

nnoremap <plug>(lsp-code-action) :<c-u>call lsp#ui#vim#code_action()<cr>
nnoremap <plug>(lsp-declaration) :<c-u>call lsp#ui#vim#declaration()<cr>
nnoremap <plug>(lsp-definition) :<c-u>call lsp#ui#vim#definition()<cr>
nnoremap <plug>(lsp-document-symbol) :<c-u>call lsp#ui#vim#document_symbol()<cr>
nnoremap <plug>(lsp-document-diagnostics) :<c-u>call lsp#ui#vim#diagnostics#document_diagnostics()<cr>
nnoremap <plug>(lsp-hover) :<c-u>call lsp#ui#vim#hover#get_hover_under_cursor()<cr>
nnoremap <plug>(lsp-next-error) :<c-u>call lsp#ui#vim#diagnostics#next_error()<cr>
nnoremap <plug>(lsp-previous-error) :<c-u>call lsp#ui#vim#diagnostics#previous_error()<cr>
nnoremap <plug>(lsp-references) :<c-u>call lsp#ui#vim#references()<cr>
nnoremap <plug>(lsp-rename) :<c-u>call lsp#ui#vim#rename()<cr>
nnoremap <plug>(lsp-type-definition) :<c-u>call lsp#ui#vim#type_definition()<cr>
nnoremap <plug>(lsp-workspace-symbol) :<c-u>call lsp#ui#vim#workspace_symbol()<cr>
nnoremap <plug>(lsp-document-format) :<c-u>call lsp#ui#vim#document_format()<cr>
vnoremap <plug>(lsp-document-format) :call lsp#ui#vim#document_range_format()<cr>
nnoremap <plug>(lsp-implementation) :<c-u>call lsp#ui#vim#implementation()<cr>
nnoremap <plug>(lsp-status) :<c-u>echo lsp#get_server_status()<cr>
