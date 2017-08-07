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

function! lsp#capabilities#has_document_symbol_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'documentSymbolProvider')
endfunction

function! lsp#capabilities#has_workspace_symbol_provider(server_name) abort
    return s:has_bool_provider(a:server_name, 'workspaceSymbolProvider')
endfunction
