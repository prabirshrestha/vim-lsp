function! s:has_bool_provider(server_name, provider) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    return !empty(l:capabilities) && has_key(l:capabilities, a:provider) && l:capabilities[a:provider] == v:true
endfunction

function! s:has_command_provider(server_name, command) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    return !empty(l:capabilities) &&
                \ has_key(l:capabilities, 'executeCommandProvider') &&
                \ type(l:capabilities['executeCommandProvider']) == type({}) &&
                \ has_key(l:capabilities['executeCommandProvider'], 'commands') &&
                \ type(l:capabilities['executeCommandProvider']['commands']) == type([]) &&
                \ index(l:capabilities['executeCommandProvider']['commands'], a:command) != -1
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

function! lsp#capabilities#has_document_highlight_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'documentHighlightProvider')
endfunction

function! lsp#capabilities#has_signature_help_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    try
        return !empty(l:capabilities['signatureHelpProvider']['triggerCharacters'])
    catch
        return 0
    endtry
endfunction

function! lsp#capabilities#has_code_lens_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    try
        return has_key(l:capabilities, 'codeLensProvider')
    catch
        return 0
    endtry
endfunction

function! lsp#capabilities#has_code_lens_resolve_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    try
        return l:capabilities['codeLensProvider']['resolveProvider'] == v:true
    catch
        return 0
    endtry
endfunction

function! lsp#capabilities#has_document_link_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    try
        return has_key(l:capabilities, 'documentLinkProvider')
    catch
        return 0
    endtry
endfunction

function! lsp#capabilities#has_document_link_resolve_provider(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    try
        return l:capabilities['documentLinkProvider']['resolveProvider'] == v:true
    catch
        return 0
    endtry
endfunction

function! lsp#capabilities#has_execute_command_provider(server_name, command) abort
    return s:has_command_provider(a:server_name, a:command)
endfunction

" [supports_did_save (boolean), { 'includeText': boolean }]
function! lsp#capabilities#get_text_document_save_registration_options(server_name) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    if !empty(l:capabilities) && has_key(l:capabilities, 'textDocumentSync')
        if type(l:capabilities['textDocumentSync']) == type({})
            if  has_key(l:capabilities['textDocumentSync'], 'save')
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
