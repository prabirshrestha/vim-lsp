let s:last_req_id = 0

function! lsp#ui#vim#get_workspace_symbols() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving workspace symbols not supported for ' . &filetype
    endif

    let l:query = input('query>')

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'workspace/Symbol',
            \ 'params': {
            \   'query': l:query,
            \ },
            \ 'on_notification': function('s:handle_symbol', [l:server, s:last_req_id, 'workspaceSymbol']),
            \ })
    endfor

    echom 'Retrieving document symbols ...'
endfunction

function! lsp#ui#vim#get_document_symbols() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving symbols not supported for ' . &filetype
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/documentSymbol',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \ },
            \ 'on_notification': function('s:handle_symbol', [l:server, s:last_req_id, 'documentSymbol']),
            \ })
    endfor

    echom 'Retrieving document symbols ...'
endfunction

function! s:handle_symbol(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        echom 'Failed to retrieve '. a:type . ' for ' . a:server
    endif

    let l:list = lsp#ui#vim#utils#to_loc_list(a:data)

    call lsp#log('............', len(l:list))

    call setqflist(l:list)

    if empty(l:list)
        echom 'No ' . a:type .' found'
    else
        echom 'Retrieved ' . a:type
        copen
    endif
endfunction

