function! s:has_provider(server_name, ...) abort
    let l:value = lsp#get_server_capabilities(a:server_name)
    for l:provider in a:000
        if empty(l:value) || type(l:value) != type({}) || !has_key(l:value, l:provider)
            return 0
        endif
        let l:value = l:value[l:provider]
    endfor
    return (type(l:value) == type(v:true) && l:value == v:true) || type(l:value) == type({})
endfunction

function! lsp#capabilities#has_declaration_provider(server_name) abort
    return s:has_provider(a:server_name, 'declarationProvider')
endfunction

function! lsp#capabilities#has_definition_provider(server_name) abort
    return s:has_provider(a:server_name, 'definitionProvider')
endfunction

function! lsp#capabilities#has_references_provider(server_name) abort
    return s:has_provider(a:server_name, 'referencesProvider')
endfunction

function! lsp#capabilities#has_hover_provider(server_name) abort
    return s:has_provider(a:server_name, 'hoverProvider')
endfunction

function! lsp#capabilities#has_rename_provider(server_name) abort
    return s:has_provider(a:server_name, 'renameProvider')
endfunction

function! lsp#capabilities#has_rename_prepare_provider(server_name) abort
    return s:has_provider(a:server_name, 'renameProvider', 'prepareProvider')
endfunction

function! lsp#capabilities#has_workspace_folders_change_notifications(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if type(l:capabilities) == type({}) && !empty(l:capabilities)
        let l:workspace = get(l:capabilities, 'workspace', {})
        if type(l:workspace) == type({}) && !empty(l:workspace)
            let l:workspace_folders = get(l:workspace, 'workspaceFolders', {})
            if type(l:workspace_folders) == type({}) && !empty(l:workspace_folders)
                if get(l:workspace_folders, 'supported', v:false) && get(l:workspace_folders, 'changeNotifications', '') ==# 'workspace/didChangeWorkspaceFolders'
                    return v:true
                endif
            endif
        endif
    endif
    return v:false
endfunction

function! lsp#capabilities#has_document_formatting_provider(server_name) abort
    return s:has_provider(a:server_name, 'documentFormattingProvider')
endfunction

function! lsp#capabilities#has_document_range_formatting_provider(server_name) abort
    return s:has_provider(a:server_name, 'documentRangeFormattingProvider')
endfunction

function! lsp#capabilities#has_document_symbol_provider(server_name) abort
    return s:has_provider(a:server_name, 'documentSymbolProvider')
endfunction

function! lsp#capabilities#has_workspace_symbol_provider(server_name) abort
    return s:has_provider(a:server_name, 'workspaceSymbolProvider')
endfunction

function! lsp#capabilities#has_implementation_provider(server_name) abort
    return s:has_provider(a:server_name, 'implementationProvider')
endfunction

function! lsp#capabilities#has_code_action_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'codeActionProvider')
        if type(l:capabilities['codeActionProvider']) == type({})
            if has_key(l:capabilities['codeActionProvider'], 'codeActionKinds') && type(l:capabilities['codeActionProvider']['codeActionKinds']) == type([])
                return len(l:capabilities['codeActionProvider']['codeActionKinds']) != 0
            endif
        endif
    endif
    return s:has_provider(a:server_name, 'codeActionProvider')
endfunction

function! lsp#capabilities#has_code_lens_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'codeLensProvider')
        return 1
    endif
    return 0
endfunction

function! lsp#capabilities#has_type_definition_provider(server_name) abort
    return s:has_provider(a:server_name, 'typeDefinitionProvider')
endfunction

function! lsp#capabilities#has_type_hierarchy_provider(server_name) abort
    return s:has_provider(a:server_name, 'typeHierarchyProvider')
endfunction

function! lsp#capabilities#has_document_highlight_provider(server_name) abort
    return s:has_provider(a:server_name, 'documentHighlightProvider')
endfunction

function! lsp#capabilities#has_folding_range_provider(server_name) abort
    return s:has_provider(a:server_name, 'foldingRangeProvider')
endfunction

function! lsp#capabilities#has_call_hierarchy_provider(server_name) abort
    return s:has_provider(a:server_name, 'callHierarchyProvider')
endfunction

function! lsp#capabilities#has_semantic_tokens(server_name) abort
    return s:has_provider(a:server_name, 'semanticTokensProvider')
endfunction

" [supports_did_save (boolean), { 'includeText': boolean }]
function! lsp#capabilities#get_text_document_save_registration_options(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'textDocumentSync')
        if type(l:capabilities['textDocumentSync']) == type({})
            let l:save_options = get(l:capabilities['textDocumentSync'], 'save', 0)
            if type(l:save_options) == type({})
              return [1, {'includeText': get(l:save_options, 'includeText', 0)}]
            else
              return [l:save_options ? 1 : 0, {'includeText': 0 }]
            endif
        else
            return [1, { 'includeText': 0 }]
        endif
    endif
    return [0, { 'includeText': 0 }]
endfunction

" supports_did_change (boolean)
function! lsp#capabilities#get_text_document_change_sync_kind(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'textDocumentSync')
        if type(l:capabilities['textDocumentSync']) == type({})
            if  has_key(l:capabilities['textDocumentSync'], 'change') && type(l:capabilities['textDocumentSync']['change']) == type(1)
                let l:val = l:capabilities['textDocumentSync']['change']
                return l:val >= 0 && l:val <= 2 ? l:val : 1
            else
                return 1
            endif
        elseif type(l:capabilities['textDocumentSync']) == type(1)
            return l:capabilities['textDocumentSync']
        else
            return 1
        endif
    endif
    return 1
endfunction

function! lsp#capabilities#has_signature_help_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'signatureHelpProvider')
        return 1
    endif
    return 0
endfunction

function! lsp#capabilities#get_signature_help_trigger_characters(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'signatureHelpProvider')
    let l:trigger_chars = []
        if type(l:capabilities['signatureHelpProvider']) == type({})
            if  has_key(l:capabilities['signatureHelpProvider'], 'triggerCharacters')
                let l:trigger_chars = l:capabilities['signatureHelpProvider']['triggerCharacters']
            endif
            " If retriggerChars exist, just treat them like triggerChars.
            if  has_key(l:capabilities['signatureHelpProvider'], 'retriggerCharacters')
                let l:trigger_chars += l:capabilities['signatureHelpProvider']['retriggerCharacters']
            endif
            return l:trigger_chars
        endif
    endif
    return []
endfunction

function! lsp#capabilities#get_code_action_kinds(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'codeActionProvider')
        if type(l:capabilities['codeActionProvider']) == type({})
            if has_key(l:capabilities['codeActionProvider'], 'codeActionKinds') && type(l:capabilities['codeActionProvider']['codeActionKinds']) == type([])
                return l:capabilities['codeActionProvider']['codeActionKinds']
            endif
        endif
    endif
    return []
endfunction

function! lsp#capabilities#has_completion_resolve_provider(server_name) abort
    return s:has_provider(a:server_name, 'completionProvider', 'resolveProvider')
endfunction
