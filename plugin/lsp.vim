if exists('g:lsp_loaded') || !exists('*json_encode') || !has('timers') || !has('lambda')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_async_completion = get(g:, 'lsp_async_completion', 0)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])
let g:lsp_signs_enabled = get(g:, 'lsp_signs_enabled', exists('*sign_define') && (has('nvim') || has('patch-8.1.0772')))
let g:lsp_signs_priority = get(g:, 'lsp_signs_priority', 10)
let g:lsp_virtual_text_enabled = get(g:, 'lsp_virtual_text_enabled', exists('*nvim_buf_set_virtual_text'))
let g:lsp_virtual_text_prefix = get(g:, 'lsp_virtual_text_prefix', '')
let g:lsp_highlights_enabled = get(g:, 'lsp_highlights_enabled', exists('*nvim_buf_add_highlight'))
let g:lsp_textprop_enabled = get(g:, 'lsp_textprop_enabled', exists('*prop_add') && !g:lsp_highlights_enabled)
let g:lsp_signs_error = get(g:, 'lsp_signs_error', {})
let g:lsp_signs_warning = get(g:, 'lsp_signs_warning', {})
let g:lsp_signs_information = get(g:, 'lsp_signs_information', {})
let g:lsp_signs_hint = get(g:, 'lsp_signs_hint', {})
let g:lsp_signs_priority = get(g:, 'lsp_signs_priority', 10)
let g:lsp_signs_priority_map = get(g:, 'lsp_signs_priority_map', {})
let g:lsp_diagnostics_enabled = get(g:, 'lsp_diagnostics_enabled', 1)
let g:lsp_diagnostics_echo_cursor = get(g:, 'lsp_diagnostics_echo_cursor', 0)
let g:lsp_diagnostics_echo_delay = get(g:, 'lsp_diagnostics_echo_delay', 500)
let g:lsp_diagnostics_float_cursor = get(g:, 'lsp_diagnostics_float_cursor', 0)
let g:lsp_diagnostics_float_delay = get(g:, 'lsp_diagnostics_float_delay', 500)
let g:lsp_next_sign_id = get(g:, 'lsp_next_sign_id', 6999)
let g:lsp_preview_keep_focus = get(g:, 'lsp_preview_keep_focus', 1)
let g:lsp_use_event_queue = get(g:, 'lsp_use_event_queue', has('nvim') || has('patch-8.1.0889'))
let g:lsp_insert_text_enabled= get(g:, 'lsp_insert_text_enabled', 1)
let g:lsp_text_edit_enabled = get(g:, 'lsp_text_edit_enabled', has('patch-8.0.1493'))
let g:lsp_highlight_references_enabled = get(g:, 'lsp_highlight_references_enabled', 0)
let g:lsp_preview_float = get(g:, 'lsp_preview_float', 1)
let g:lsp_preview_autoclose = get(g:, 'lsp_preview_autoclose', 1)
let g:lsp_preview_doubletap = get(g:, 'lsp_preview_doubletap', [function('lsp#ui#vim#output#focuspreview')])
let g:lsp_peek_alignment = get(g:, 'lsp_peek_alignment', 'center')
let g:lsp_preview_max_width = get(g:, 'lsp_preview_max_width', -1)
let g:lsp_preview_max_height = get(g:, 'lsp_preview_max_height', -1)
let g:lsp_signature_help_enabled = get(g:, 'lsp_signature_help_enabled', 1)
let g:lsp_fold_enabled = get(g:, 'lsp_fold_enabled', 1)
let g:lsp_hover_conceal = get(g:, 'lsp_hover_conceal', 1)
let g:lsp_ignorecase = get(g:, 'lsp_ignorecase', &ignorecase)
let g:lsp_semantic_enabled = get(g:, 'lsp_semantic_enabled', 0)
let g:lsp_text_document_did_save_delay = get(g:, 'lsp_text_document_did_save_delay', -1)
let g:lsp_completion_resolve_timeout = get(g:, 'lsp_completion_resolve_timeout', 200)

let g:lsp_get_vim_completion_item = get(g:, 'lsp_get_vim_completion_item', [function('lsp#omni#default_get_vim_completion_item')])
let g:lsp_get_supported_capabilities = get(g:, 'lsp_get_supported_capabilities', [function('lsp#default_get_supported_capabilities')])

if g:lsp_auto_enable
    augroup lsp_auto_enable
        autocmd!
        autocmd VimEnter * call lsp#enable()
    augroup END
endif

command! -range -nargs=* -complete=customlist,lsp#ui#vim#code_action#complete LspCodeAction call lsp#ui#vim#code_action#do({
      \   'sync': v:false,
      \   'selection': <range> != 0,
      \   'query_filter': empty('<args>') ? v:false : {action -> get(action, 'kind', '') =~# '^<args>'}
      \ })
command! -range -nargs=* -complete=customlist,lsp#ui#vim#code_action#complete LspCodeActionSync call lsp#ui#vim#code_action#do({
      \   'sync': v:true,
      \   'selection': <range> != 0,
      \   'query_filter': empty('<args>') ? v:false : {action -> get(action, 'kind', '') =~# '^<args>'}
      \ })
command! LspDeclaration call lsp#ui#vim#declaration(0, <q-mods>)
command! LspPeekDeclaration call lsp#ui#vim#declaration(1)
command! LspDefinition call lsp#ui#vim#definition(0, <q-mods>)
command! LspPeekDefinition call lsp#ui#vim#definition(1)
command! LspDocumentSymbol call lsp#ui#vim#document_symbol()
command! LspDocumentDiagnostics call lsp#ui#vim#diagnostics#document_diagnostics()
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspHover call lsp#ui#vim#hover#get_hover_under_cursor()
command! -nargs=* LspNextError call lsp#ui#vim#diagnostics#next_error(<f-args>)
command! -nargs=* LspPreviousError call lsp#ui#vim#diagnostics#previous_error(<f-args>)
command! -nargs=* LspNextWarning call lsp#ui#vim#diagnostics#next_warning(<f-args>)
command! -nargs=* LspPreviousWarning call lsp#ui#vim#diagnostics#previous_warning(<f-args>)
command! -nargs=* LspNextDiagnostic call lsp#ui#vim#diagnostics#next_diagnostic(<f-args>)
command! -nargs=* LspPreviousDiagnostic call lsp#ui#vim#diagnostics#previous_diagnostic(<f-args>)
command! LspReferences call lsp#ui#vim#references()
command! LspRename call lsp#ui#vim#rename()
command! LspTypeDefinition call lsp#ui#vim#type_definition(0, <q-mods>)
command! LspTypeHierarchy call lsp#ui#vim#type_hierarchy()
command! LspPeekTypeDefinition call lsp#ui#vim#type_definition(1)
command! LspWorkspaceSymbol call lsp#ui#vim#workspace_symbol()
command! -range LspDocumentFormat call lsp#ui#vim#document_format()
command! -range LspDocumentFormatSync call lsp#ui#vim#document_format_sync()
command! -range LspDocumentRangeFormat call lsp#ui#vim#document_range_format()
command! -range LspDocumentRangeFormatSync call lsp#ui#vim#document_range_format_sync()
command! LspImplementation call lsp#ui#vim#implementation(0, <q-mods>)
command! LspPeekImplementation call lsp#ui#vim#implementation(1)
command! -nargs=0 LspStatus call lsp#print_server_status()
command! LspNextReference call lsp#ui#vim#references#jump(+1)
command! LspPreviousReference call lsp#ui#vim#references#jump(-1)
command! -nargs=? -complete=customlist,lsp#server_complete LspStopServer call lsp#ui#vim#stop_server(<f-args>)
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspSignatureHelp call lsp#ui#vim#signature_help#get_signature_help_under_cursor()
command! LspDocumentFold call lsp#ui#vim#folding#fold(0)
command! LspDocumentFoldSync call lsp#ui#vim#folding#fold(1)
command! -nargs=? LspSemanticScopes call lsp#ui#vim#semantic#display_scope_tree(<args>)

nnoremap <plug>(lsp-code-action) :<c-u>call lsp#ui#vim#code_action()<cr>
nnoremap <plug>(lsp-declaration) :<c-u>call lsp#ui#vim#declaration(0)<cr>
nnoremap <plug>(lsp-peek-declaration) :<c-u>call lsp#ui#vim#declaration(1)<cr>
nnoremap <plug>(lsp-definition) :<c-u>call lsp#ui#vim#definition(0)<cr>
nnoremap <plug>(lsp-peek-definition) :<c-u>call lsp#ui#vim#definition(1)<cr>
nnoremap <plug>(lsp-document-symbol) :<c-u>call lsp#ui#vim#document_symbol()<cr>
nnoremap <plug>(lsp-document-diagnostics) :<c-u>call lsp#ui#vim#diagnostics#document_diagnostics()<cr>
nnoremap <plug>(lsp-hover) :<c-u>call lsp#ui#vim#hover#get_hover_under_cursor()<cr>
nnoremap <plug>(lsp-preview-close) :<c-u>call lsp#ui#vim#output#closepreview()<cr>
nnoremap <plug>(lsp-preview-focus) :<c-u>call lsp#ui#vim#output#focuspreview()<cr>
nnoremap <plug>(lsp-next-error) :<c-u>call lsp#ui#vim#diagnostics#next_error()<cr>
nnoremap <plug>(lsp-next-error-nowrap) :<c-u>call lsp#ui#vim#diagnostics#next_error("--nowrap")<cr>
nnoremap <plug>(lsp-previous-error) :<c-u>call lsp#ui#vim#diagnostics#previous_error()<cr>
nnoremap <plug>(lsp-previous-error-nowrap) :<c-u>call lsp#ui#vim#diagnostics#previous_error("--nowrap")<cr>
nnoremap <plug>(lsp-next-warning) :<c-u>call lsp#ui#vim#diagnostics#next_warning()<cr>
nnoremap <plug>(lsp-next-warning-nowrap) :<c-u>call lsp#ui#vim#diagnostics#next_warning("--nowrap")<cr>
nnoremap <plug>(lsp-previous-warning) :<c-u>call lsp#ui#vim#diagnostics#previous_warning()<cr>
nnoremap <plug>(lsp-previous-warning-nowrap) :<c-u>call lsp#ui#vim#diagnostics#previous_warning("--nowrap")<cr>
nnoremap <plug>(lsp-next-diagnostic) :<c-u>call lsp#ui#vim#diagnostics#next_diagnostic()<cr>
nnoremap <plug>(lsp-next-diagnostic-nowrap) :<c-u>call lsp#ui#vim#diagnostics#next_diagnostic("--nowrap")<cr>
nnoremap <plug>(lsp-previous-diagnostic) :<c-u>call lsp#ui#vim#diagnostics#previous_diagnostic()<cr>
nnoremap <plug>(lsp-previous-diagnostic-nowrap) :<c-u>call lsp#ui#vim#diagnostics#previous_diagnostic("--nowrap")<cr>
nnoremap <plug>(lsp-references) :<c-u>call lsp#ui#vim#references()<cr>
nnoremap <plug>(lsp-rename) :<c-u>call lsp#ui#vim#rename()<cr>
nnoremap <plug>(lsp-type-definition) :<c-u>call lsp#ui#vim#type_definition(0)<cr>
nnoremap <plug>(lsp-type-hierarchy) :<c-u>call lsp#ui#vim#type_hierarchy()<cr>
nnoremap <plug>(lsp-peek-type-definition) :<c-u>call lsp#ui#vim#type_definition(1)<cr>
nnoremap <plug>(lsp-workspace-symbol) :<c-u>call lsp#ui#vim#workspace_symbol()<cr>
nnoremap <plug>(lsp-document-format) :<c-u>call lsp#ui#vim#document_format()<cr>
vnoremap <plug>(lsp-document-format) :<Home>silent <End>call lsp#ui#vim#document_range_format()<cr>
nnoremap <plug>(lsp-document-range-format) :<c-u>set opfunc=lsp#ui#vim#document_range_format_opfunc<cr>g@
xnoremap <plug>(lsp-document-range-format) :<Home>silent <End>call lsp#ui#vim#document_range_format()<cr>
nnoremap <plug>(lsp-implementation) :<c-u>call lsp#ui#vim#implementation(0)<cr>
nnoremap <plug>(lsp-peek-implementation) :<c-u>call lsp#ui#vim#implementation(1)<cr>
nnoremap <plug>(lsp-status) :<c-u>echo lsp#get_server_status()<cr>
nnoremap <plug>(lsp-next-reference) :<c-u>call lsp#ui#vim#references#jump(+1)<cr>
nnoremap <plug>(lsp-previous-reference) :<c-u>call lsp#ui#vim#references#jump(-1)<cr>
nnoremap <plug>(lsp-signature-help) :<c-u>call lsp#ui#vim#signature_help#get_signature_help_under_cursor()<cr>
