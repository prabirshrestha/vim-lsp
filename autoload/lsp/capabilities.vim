function! s:has_bool_provider(server_name, ...) abort
    let l:value = lsp#get_server_capabilities(a:server_name)
    for l:provider in a:000
        if empty(l:value) || type(l:value) != type({}) || !has_key(l:value, l:provider)
            return 0
        endif
        let l:value = l:value[l:provider]
    endfor
    return type(l:value) == type(v:true) && l:value == v:true
endfunction

function! lsp#capabilities#has_declaration_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'declarationProvider')
endfunction

function! lsp#capabilities#has_definition_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'definitionProvider')
endfunction

function! lsp#capabilities#has_references_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'referencesProvider')
endfunction

function! lsp#capabilities#has_hover_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'hoverProvider')
endfunction

function! lsp#capabilities#has_rename_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'renameProvider')
endfunction

function! lsp#capabilities#has_rename_prepare_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'renameProvider', 'prepareProvider')
endfunction

function! lsp#capabilities#has_document_formatting_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'documentFormattingProvider')
endfunction

function! lsp#capabilities#has_document_range_formatting_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'documentRangeFormattingProvider')
endfunction

function! lsp#capabilities#has_document_symbol_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'documentSymbolProvider')
endfunction

function! lsp#capabilities#has_workspace_symbol_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'workspaceSymbolProvider')
endfunction

function! lsp#capabilities#has_implementation_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'implementationProvider')
endfunction

function! lsp#capabilities#has_code_action_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'codeActionProvider')
endfunction

function! lsp#capabilities#has_type_definition_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'typeDefinitionProvider')
endfunction

function! lsp#capabilities#get_execute_command_commands(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'executeCommandProvider')
        if type(l:capabilities['executeCommandProvider']) == type({})
            let l:provider = l:capabilities['executeCommandProvider']
            if has_key(l:provider, 'commands') && type(l:provider['commands']) == type([])
                return l:provider['commands']
            endif
        endif
    endif
    return []
endfunction

" [supports_did_save (boolean), { 'includeText': boolean }]
function! lsp#capabilities#get_text_document_save_registration_options(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'textDocumentSync')
        if type(l:capabilities['textDocumentSync']) == type({})
            if has_key(l:capabilities['textDocumentSync'], 'save')
                return [1, {
                    \ 'includeText': has_key(l:capabilities['textDocumentSync']['save'], 'includeText') ? l:capabilities['textDocumentSync']['save']['includeText'] : 0,
                    \ }]
            else
                return [0, { 'includeText': 0 }]
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
            if has_key(l:capabilities['textDocumentSync'], 'change') && type(l:capabilities['textDocumentSync']['change']) == type(1)
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

function! lsp#capabilities#has_code_lens_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    return !empty(l:capabilities) && has_key(l:capabilities, 'codeLensProvider')
endfunction

function! lsp#capabilities#has_code_lens_resolve_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'codeLensProvider')
        if type(l:capabilities['codeLensProvider']) == type({})
            let l:provider = l:capabilities['codeLensProvider']
            if has_key(l:provider, 'resolveProvider') && type(l:provider['resolveProvider']) == type(v:true)
                return l:provider['resolveProvider'] == v:true
            endif
        endif
    endif
    return 0
endfunction
