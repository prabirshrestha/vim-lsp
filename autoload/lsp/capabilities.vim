function! s:has_bool_provider(server_name, provider) abort
    let l:capabilities = lsp#get_server_capabilities(a:server_name)
    return !empty(l:capabilities) && has_key(l:capabilities, a:provider) && l:capabilities[a:provider] == v:true
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
