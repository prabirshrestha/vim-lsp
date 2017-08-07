let s:last_req_id = 0

function! lsp#ui#vim#definition() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_definition_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving definition not supported for ' . &filetype
        return
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

    echom 'Retrieving definition ...'
endfunction

function! lsp#ui#vim#references() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_references_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving references not supported for ' . &filetype
        return
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
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_hover_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving hover not supported for ' . &filetype
        return
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

function! lsp#ui#vim#rename() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_rename_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        echom 'Renaming not supported for ' . &filetype
        return
    endif

    let l:new_name = input('new name>')

    if empty(l:new_name)
        echom '... Renaming aborted ...'
        return
    endif

    " TODO: ask the user which server it should use to rename if there are multiple
    let l:server = l:servers[0]
    " needs to flush existing open buffers
    call lsp#send_request(l:server, {
        \ 'method': 'textDocument/rename',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \   'newName': l:new_name,
        \ },
        \ 'on_notification': function('s:handle_workspace_edit', [l:server, s:last_req_id, 'rename']),
        \ })

    echom ' ... Renaming ...'
endfunction

function! lsp#ui#vim#workspace_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving workspace symbols not supported for ' . &filetype
        return
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

function! lsp#ui#vim#document_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        echom 'Retrieving symbols not supported for ' . &filetype
        return
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
        return
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
        return
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
        return
    endif

    if !has_key(a:data['response'], 'result')
        return
    endif

    if empty(a:data['response']['result'])
        echom 'No ' . a:type .' found'
        return
    endif

    let l:contents = a:data['response']['result']['contents']

    if type(l:contents) == type('')
        let l:contents = [{ 'text': s:markdown_to_text(l:contents) }]
    elseif type(l:contents) == type([])
        let l:contents = []
        for l:content in a:data['response']['result']['contents']
            if type(l:content) == type('')
                call add(l:contents, { 'text': s:markdown_to_text(l:content) })
            elseif type(l:content) == type({})
                call add(l:contents, { 'text': s:markdown_to_text(l:content['value']) })
            endif
        endfor
    endif

    call setqflist(l:contents)

    " autocmd FileType qf setlocal wrap

    if empty(l:contents)
        echom 'No ' . a:type .' found'
    else
        echom 'Retrieved ' . a:type
        copen
    endif
endfunction

function! s:handle_workspace_edit(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        echom 'Failed to retrieve '. a:type . ' for ' . a:server
        return
    endif

    call s:apply_workspace_edits(a:data['response']['result'])

    echom 'Renamed'
endfunction

" @params
"   workspace_edits - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#workspaceedit
function! s:apply_workspace_edits(workspace_edits) abort
    if has_key(a:workspace_edits, 'changes')
        for [l:uri, l:text_edits] in items(a:workspace_edits['changes'])
            let l:path = lsp#uri_to_path(l:uri)
            let l:cmd = 'edit ' . l:path
            for l:text_edit in l:text_edits
                let l:start_line = l:text_edit['range']['start']['line'] + 1
                let l:start_character = l:text_edit['range']['start']['character'] + 1
                let l:end_line = l:text_edit['range']['end']['line'] + 1
                let l:end_character = l:text_edit['range']['end']['character'] + 1
                let l:new_text = l:text_edit['newText']
                let l:cmd = l:cmd . printf(' | execute "normal! %dG%d|v%dG%d|c%s"', l:start_line, l:start_character, l:end_line, l:end_character, new_text)
            endfor
            call lsp#log('s:apply_workspace_edits', l:cmd)
            execute l:cmd
        endfor
    endif
    " TODO: support documentChanges
endfunction

function! s:markdown_to_text(markdown) abort
    " TODO: convert markdown to normal text
    return a:markdown
endfunction
