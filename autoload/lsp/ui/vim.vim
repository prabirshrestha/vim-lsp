let s:last_req_id = 0

function! lsp#ui#vim#definition() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving goto definition not supported for ' . &filetype
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/definition',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_location', [l:server, s:last_req_id, 'definition']),
            \ })
    endfor

    echom 'Retrieving goto definition ...'
endfunction

function! lsp#ui#vim#references() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving references not supported for ' . &filetype
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/references',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \   'includeDeclaration': v:false,
            \ },
            \ 'on_notification': function('s:handle_location', [l:server, s:last_req_id, 'references']),
            \ })
    endfor

    echom 'Retrieving references ...'
endfunction

function! lsp#ui#vim#hover() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving hover not supported for ' . &filetype
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/hover',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_hover', [l:server, s:last_req_id, 'hover']),
            \ })
    endfor

    echom 'Retrieving hover ...'
endfunction

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

    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:data)

    call setqflist(l:list)

    if empty(l:list)
        echom 'No ' . a:type .' found'
    else
        echom 'Retrieved ' . a:type
        copen
    endif
endfunction

function! s:handle_location(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        echom 'Failed to retrieve '. a:type . ' for ' . a:server
    endif

    let l:list = lsp#ui#vim#utils#locations_to_loc_list(a:data)

    call setqflist(l:list)

    if empty(l:list)
        echom 'No ' . a:type .' found'
    else
        echom 'Retrieved ' . a:type
        copen
    endif
endfunction

function! s:handle_hover(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        echom 'Failed to retrieve '. a:type . ' for ' . a:server
    endif

    if !has_key(a:data['response'], 'result')
        return
    endif

    let l:contents = a:data['response']['result']['contents']

    call setqflist([{ 'text': l:contents }])

    " autocmd FileType qf setlocal wrap

    if empty(l:contents)
        echom 'No ' . a:type .' found'
    else
        echom 'Retrieved ' . a:type
        copen
    endif
endfunction
