if exists('g:lsp_loaded') || !exists('*json_encode') || !has('timers') || !has('lambda')
    finish
endif
let g:lsp_loaded = 1

let g:lsp_use_lua = get(g:, 'lsp_use_lua', has('nvim-0.4.0') || (has('lua') && has('patch-8.2.0775')))
let g:lsp_auto_enable = get(g:, 'lsp_auto_enable', 1)
let g:lsp_async_completion = get(g:, 'lsp_async_completion', 0)
let g:lsp_log_file = get(g:, 'lsp_log_file', '')
let g:lsp_log_verbose = get(g:, 'lsp_log_verbose', 1)
let g:lsp_debug_servers = get(g:, 'lsp_debug_servers', [])
let g:lsp_format_sync_timeout = get(g:, 'lsp_format_sync_timeout', -1)
let g:lsp_max_buffer_size = get(g:, 'lsp_max_buffer_size', 5000000)

let g:lsp_completion_documentation_enabled = get(g:, 'lsp_completion_documentation_enabled', 1)
let g:lsp_completion_documentation_delay = get(g:, 'lsp_completion_documention_delay', 80)

let g:lsp_diagnostics_enabled = get(g:, 'lsp_diagnostics_enabled', 1)
let g:lsp_diagnostics_echo_cursor = get(g:, 'lsp_diagnostics_echo_cursor', 0)
let g:lsp_diagnostics_echo_delay = get(g:, 'lsp_diagnostics_echo_delay', 500)
let g:lsp_diagnostics_float_cursor = get(g:, 'lsp_diagnostics_float_cursor', 0)
let g:lsp_diagnostics_float_delay = get(g:, 'lsp_diagnostics_float_delay', 500)
let g:lsp_diagnostics_highlights_enabled = get(g:, 'lsp_diagnostics_highlights_enabled', lsp#utils#_has_highlights())
let g:lsp_diagnostics_highlights_insert_mode_enabled = get(g:, 'lsp_diagnostics_highlights_insert_mode_enabled', 1)
let g:lsp_diagnostics_highlights_delay = get(g:, 'lsp_diagnostics_highlights_delay', 500)
let g:lsp_diagnostics_signs_enabled = get(g:, 'lsp_diagnostics_signs_enabled', lsp#utils#_has_signs())
let g:lsp_diagnostics_signs_insert_mode_enabled = get(g:, 'lsp_diagnostics_signs_insert_mode_enabled', 1)
let g:lsp_diagnostics_signs_delay = get(g:, 'lsp_diagnostics_signs_delay', 500)
let g:lsp_diagnostics_signs_error = get(g:, 'lsp_diagnostics_signs_error', {})
let g:lsp_diagnostics_signs_warning = get(g:, 'lsp_diagnostics_signs_warning', {})
let g:lsp_diagnostics_signs_information = get(g:, 'lsp_diagnostics_signs_information', {})
let g:lsp_diagnostics_signs_hint = get(g:, 'lsp_diagnostics_signs_hint', {})
let g:lsp_diagnostics_signs_priority = get(g:, 'lsp_diagnostics_signs_priority', 10)
let g:lsp_diagnostics_signs_priority_map = get(g:, 'lsp_diagnostics_signs_priority_map', {})
let g:lsp_diagnostics_virtual_text_enabled = get(g:, 'lsp_diagnostics_virtual_text_enabled', lsp#utils#_has_virtual_text())
let g:lsp_diagnostics_virtual_text_insert_mode_enabled = get(g:, 'lsp_diagnostics_virtual_text_insert_mode_enabled', 0)
let g:lsp_diagnostics_virtual_text_delay = get(g:, 'lsp_diagnostics_virtual_text_delay', 500)
let g:lsp_diagnostics_virtual_text_prefix = get(g:, 'lsp_diagnostics_virtual_text_prefix', '')

let g:lsp_document_code_action_signs_enabled = get(g:, 'lsp_document_code_action_signs_enabled', 1)
let g:lsp_document_code_action_signs_delay = get(g:, 'lsp_document_code_action_signs_delay', 500)
let g:lsp_document_code_action_signs_hint = get(g:, 'lsp_document_code_action_signs_hint', {})
let g:lsp_document_code_action_signs_priority = get(g:, 'lsp_document_code_action_signs_priority', 10)

let g:lsp_tree_incoming_prefix = get(g:, 'lsp_tree_incoming_prefix', '<= ')

let g:lsp_preview_keep_focus = get(g:, 'lsp_preview_keep_focus', 1)
let g:lsp_use_event_queue = get(g:, 'lsp_use_event_queue', has('nvim') || has('patch-8.1.0889'))
let g:lsp_insert_text_enabled= get(g:, 'lsp_insert_text_enabled', 1)
let g:lsp_text_edit_enabled = get(g:, 'lsp_text_edit_enabled', has('patch-8.0.1493'))
let g:lsp_document_highlight_enabled = get(g:, 'lsp_document_highlight_enabled', 1)
let g:lsp_document_highlight_delay = get(g:, 'lsp_document_highlight_delay', 350)
let g:lsp_preview_float = get(g:, 'lsp_preview_float', 1)
let g:lsp_preview_autoclose = get(g:, 'lsp_preview_autoclose', 1)
let g:lsp_preview_doubletap = get(g:, 'lsp_preview_doubletap', [function('lsp#ui#vim#output#focuspreview')])
let g:lsp_peek_alignment = get(g:, 'lsp_peek_alignment', 'center')
let g:lsp_preview_max_width = get(g:, 'lsp_preview_max_width', -1)
let g:lsp_preview_max_height = get(g:, 'lsp_preview_max_height', -1)
let g:lsp_signature_help_enabled = get(g:, 'lsp_signature_help_enabled', 1)
let g:lsp_signature_help_delay = get(g:, 'lsp_signature_help_delay', 200)
let g:lsp_show_workspace_edits = get(g:, 'lsp_show_workspace_edits', 0)
let g:lsp_fold_enabled = get(g:, 'lsp_fold_enabled', 1)
let g:lsp_hover_conceal = get(g:, 'lsp_hover_conceal', 1)
let g:lsp_hover_ui = get(g:, 'lsp_hover_ui', '')
let g:lsp_ignorecase = get(g:, 'lsp_ignorecase', &ignorecase)
let g:lsp_semantic_enabled = get(g:, 'lsp_semantic_enabled', 0)
let g:lsp_semantic_delay = get(g:, 'lsp_semantic_delay', 500)
let g:lsp_text_document_did_save_delay = get(g:, 'lsp_text_document_did_save_delay', -1)
let g:lsp_completion_resolve_timeout = get(g:, 'lsp_completion_resolve_timeout', 200)
let g:lsp_tagfunc_source_methods = get(g:, 'lsp_tagfunc_source_methods', ['definition', 'declaration', 'implementation', 'typeDefinition'])
let g:lsp_show_message_request_enabled = get(g:, 'lsp_show_message_request_enabled', 1)
let g:lsp_show_message_log_level = get(g:, 'lsp_show_message_log_level', 'warning')
let g:lsp_work_done_progress_enabled = get(g:, 'lsp_work_done_progress_enabled', 0)
let g:lsp_untitled_buffer_enabled = get(g:, 'lsp_untitled_buffer_enabled', 1)

let g:lsp_get_supported_capabilities = get(g:, 'lsp_get_supported_capabilities', [function('lsp#default_get_supported_capabilities')])

let g:lsp_experimental_workspace_folders = get(g:, 'lsp_experimental_workspace_folders', 0)

if g:lsp_auto_enable
    augroup lsp_auto_enable
        autocmd!
        autocmd VimEnter * call lsp#enable()
    augroup END
endif

command! LspAddTreeCallHierarchyIncoming call lsp#ui#vim#add_tree_call_hierarchy_incoming()
command! LspCallHierarchyIncoming call lsp#ui#vim#call_hierarchy_incoming({})
command! LspCallHierarchyOutgoing call lsp#ui#vim#call_hierarchy_outgoing()
command! -range -nargs=* -complete=customlist,lsp#ui#vim#code_action#complete LspCodeAction call lsp#ui#vim#code_action#do({
      \   'sync': v:false,
      \   'selection': <range> != 0,
      \   'query': '<args>'
      \ })
command! -range -nargs=* -complete=customlist,lsp#ui#vim#code_action#complete LspCodeActionSync call lsp#ui#vim#code_action#do({
      \   'sync': v:true,
      \   'selection': <range> != 0,
      \   'query': '<args>'
      \ })
command! LspCodeLens call lsp#ui#vim#code_lens#do({})
command! LspDeclaration call lsp#ui#vim#declaration(0, <q-mods>)
command! LspPeekDeclaration call lsp#ui#vim#declaration(1)
command! LspDefinition call lsp#ui#vim#definition(0, <q-mods>)
command! LspPeekDefinition call lsp#ui#vim#definition(1)
command! LspDocumentSymbol call lsp#ui#vim#document_symbol()
command! LspDocumentSymbolSearch call lsp#internal#document_symbol#search#do({})
command! -nargs=? LspDocumentDiagnostics call lsp#internal#diagnostics#document_diagnostics_command#do(
            \ extend({}, lsp#utils#args#_parse(<q-args>, {
            \   'buffers': {'type': type('')},
            \ })))
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspHover call lsp#internal#document_hover#under_cursor#do(
            \ extend({}, lsp#utils#args#_parse(<q-args>, {
            \   'ui': { 'type': type('') },
            \ })))
command! -nargs=* LspNextError call lsp#internal#diagnostics#movement#_next_error(<f-args>)
command! -nargs=* LspPreviousError call lsp#internal#diagnostics#movement#_previous_error(<f-args>)
command! -nargs=* LspNextWarning call lsp#internal#diagnostics#movement#_next_warning(<f-args>)
command! -nargs=* LspPreviousWarning call lsp#internal#diagnostics#movement#_previous_warning(<f-args>)
command! -nargs=* LspNextDiagnostic call lsp#internal#diagnostics#movement#_next_diagnostics(<f-args>)
command! -nargs=* LspPreviousDiagnostic call lsp#internal#diagnostics#movement#_previous_diagnostics(<f-args>)
command! LspReferences call lsp#ui#vim#references()
command! LspRename call lsp#ui#vim#rename()
command! LspTypeDefinition call lsp#ui#vim#type_definition(0, <q-mods>)
command! LspTypeHierarchy call lsp#internal#type_hierarchy#show()
command! LspPeekTypeDefinition call lsp#ui#vim#type_definition(1)
command! -nargs=? LspWorkspaceSymbol call lsp#ui#vim#workspace_symbol(<q-args>)
command! -nargs=? LspWorkspaceSymbolSearch call lsp#internal#workspace_symbol#search#do({'query': <q-args>})
command! -range LspDocumentFormat call lsp#internal#document_formatting#format({ 'bufnr': bufnr('%') })
command! -range -nargs=? LspDocumentFormatSync call lsp#internal#document_formatting#format(
            \ extend({'bufnr': bufnr('%'), 'sync': 1 }, lsp#utils#args#_parse(<q-args>, {
            \   'timeout': {'type': type(0)},
            \   'sleep': {'type': type(0)},
            \ })))
command! -range LspDocumentRangeFormat call lsp#internal#document_range_formatting#format({ 'bufnr': bufnr('%') })
command! -range -nargs=? LspDocumentRangeFormatSync call lsp#internal#document_range_formatting#format(
            \ extend({'bufnr': bufnr('%'), 'sync': 1 }, lsp#utils#args#_parse(<q-args>, {
            \   'timeout': {'type': type(0)},
            \   'sleep': {'type': type(0)},
            \ })))
command! LspImplementation call lsp#ui#vim#implementation(0, <q-mods>)
command! LspPeekImplementation call lsp#ui#vim#implementation(1)
command! -nargs=0 LspStatus call lsp#print_server_status()
command! LspNextReference call lsp#internal#document_highlight#jump(+1)
command! LspPreviousReference call lsp#internal#document_highlight#jump(-1)
command! -nargs=? -complete=customlist,lsp#server_complete LspStopServer call lsp#ui#vim#stop_server(<f-args>)
command! -nargs=? -complete=customlist,lsp#utils#empty_complete LspSignatureHelp call lsp#ui#vim#signature_help#get_signature_help_under_cursor()
command! LspDocumentFold call lsp#ui#vim#folding#fold(0)
command! LspDocumentFoldSync call lsp#ui#vim#folding#fold(1)
command! -nargs=0 LspSemanticTokenTypes echo lsp#internal#semantic#get_token_types()
command! -nargs=0 LspSemanticTokenModifiers echo lsp#internal#semantic#get_token_modifiers()

nnoremap <silent> <plug>(lsp-call-hierarchy-incoming) :<c-u>call lsp#ui#vim#call_hierarchy_incoming({})<cr>
nnoremap <silent> <plug>(lsp-call-hierarchy-outgoing) :<c-u>call lsp#ui#vim#call_hierarchy_outgoing()<cr>
nnoremap <silent> <plug>(lsp-code-action) :<c-u>call lsp#ui#vim#code_action()<cr>
nnoremap <silent> <plug>(lsp-code-lens) :<c-u>call lsp#ui#vim#code_lens()<cr>
nnoremap <silent> <plug>(lsp-declaration) :<c-u>call lsp#ui#vim#declaration(0)<cr>
nnoremap <silent> <plug>(lsp-peek-declaration) :<c-u>call lsp#ui#vim#declaration(1)<cr>
nnoremap <silent> <plug>(lsp-definition) :<c-u>call lsp#ui#vim#definition(0)<cr>
nnoremap <silent> <plug>(lsp-peek-definition) :<c-u>call lsp#ui#vim#definition(1)<cr>
nnoremap <silent> <plug>(lsp-document-symbol) :<c-u>call lsp#ui#vim#document_symbol()<cr>
nnoremap <silent> <plug>(lsp-document-symbol-search) :<c-u>call lsp#internal#document_symbol#search#do({})<cr>
nnoremap <silent> <plug>(lsp-document-diagnostics) :<c-u>call lsp#internal#diagnostics#document_diagnostics_command#do({})<cr>
nnoremap <silent> <plug>(lsp-hover) :<c-u>call lsp#internal#document_hover#under_cursor#do({})<cr>
nnoremap <silent> <plug>(lsp-hover-float) :<c-u>call lsp#internal#document_hover#under_cursor#do({ 'ui': 'float' })<cr>
nnoremap <silent> <plug>(lsp-hover-preview) :<c-u>call lsp#internal#document_hover#under_cursor#do({ 'ui': 'preview' })<cr>
nnoremap <silent> <plug>(lsp-preview-close) :<c-u>call lsp#ui#vim#output#closepreview()<cr>
nnoremap <silent> <plug>(lsp-preview-focus) :<c-u>call lsp#ui#vim#output#focuspreview()<cr>
nnoremap <silent> <plug>(lsp-next-error) :<c-u>call lsp#internal#diagnostics#movement#_next_error()<cr>
nnoremap <silent> <plug>(lsp-next-error-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_next_error("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-previous-error) :<c-u>call lsp#internal#diagnostics#movement#_previous_error()<cr>
nnoremap <silent> <plug>(lsp-previous-error-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_previous_error("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-next-warning) :<c-u>call lsp#internal#diagnostics#movement#_next_warning()<cr>
nnoremap <silent> <plug>(lsp-next-warning-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_next_warning("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-previous-warning) :<c-u>call lsp#internal#diagnostics#movement#_previous_warning()<cr>
nnoremap <silent> <plug>(lsp-previous-warning-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_previous_warning("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-next-diagnostic) :<c-u>call lsp#internal#diagnostics#movement#_next_diagnostics()<cr>
nnoremap <silent> <plug>(lsp-next-diagnostic-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_next_diagnostics("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-previous-diagnostic) :<c-u>call lsp#internal#diagnostics#movement#_previous_diagnostics()<cr>
nnoremap <silent> <plug>(lsp-previous-diagnostic-nowrap) :<c-u>call lsp#internal#diagnostics#movement#_previous_diagnostics("-wrap=0")<cr>
nnoremap <silent> <plug>(lsp-references) :<c-u>call lsp#ui#vim#references()<cr>
nnoremap <silent> <plug>(lsp-rename) :<c-u>call lsp#ui#vim#rename()<cr>
nnoremap <silent> <plug>(lsp-type-definition) :<c-u>call lsp#ui#vim#type_definition(0)<cr>
nnoremap <silent> <plug>(lsp-type-hierarchy) :<c-u>call lsp#internal#type_hierarchy#show()<cr>
nnoremap <silent> <plug>(lsp-peek-type-definition) :<c-u>call lsp#ui#vim#type_definition(1)<cr>
nnoremap <silent> <plug>(lsp-workspace-symbol) :<c-u>call lsp#ui#vim#workspace_symbol('')<cr>
nnoremap <silent> <plug>(lsp-workspace-symbol-search) :<c-u>call lsp#internal#workspace_symbol#search#do({})<cr>
nnoremap <silent> <plug>(lsp-document-format) :<c-u>call lsp#internal#document_formatting#format({ 'bufnr': bufnr('%') })<cr>
vnoremap <silent> <plug>(lsp-document-format) :<Home>silent <End>call lsp#internal#document_range_formatting#format({ 'bufnr': bufnr('%') })<cr>
nnoremap <silent> <plug>(lsp-document-range-format) :<c-u>set opfunc=lsp#internal#document_range_formatting#opfunc<cr>g@
xnoremap <silent> <plug>(lsp-document-range-format) :<Home>silent <End>call lsp#internal#document_range_formatting#format({ 'bufnr': bufnr('%') })<cr>
nnoremap <silent> <plug>(lsp-implementation) :<c-u>call lsp#ui#vim#implementation(0)<cr>
nnoremap <silent> <plug>(lsp-peek-implementation) :<c-u>call lsp#ui#vim#implementation(1)<cr>
nnoremap <silent> <plug>(lsp-status) :<c-u>echo lsp#get_server_status()<cr>
nnoremap <silent> <plug>(lsp-next-reference) :<c-u>call lsp#internal#document_highlight#jump(+1)<cr>
nnoremap <silent> <plug>(lsp-previous-reference) :<c-u>call lsp#internal#document_highlight#jump(-1)<cr>
nnoremap <silent> <plug>(lsp-signature-help) :<c-u>call lsp#ui#vim#signature_help#get_signature_help_under_cursor()<cr>
