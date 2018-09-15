let s:last_req_id = 0

function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
endfunction

function! lsp#ui#vim#implementation() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_implementation_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving implementation')
        return
    endif
    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/implementation',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'implementation']),
            \ })
    endfor

    echo 'Retrieving implementation ...'
endfunction

function! lsp#ui#vim#type_definition() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_type_definition_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving type definition')
        return
    endif
    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/typeDefinition',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'type definition']),
            \ })
    endfor

    echo 'Retrieving type definition ...'
endfunction

function! lsp#ui#vim#definition() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_definition_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1
    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving definition')
        return
    endif

    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 1 }
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/definition',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'definition']),
            \ })
    endfor

    echo 'Retrieving definition ...'
endfunction

function! lsp#ui#vim#references() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_references_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_req_id': s:last_req_id, 'jump_if_one': 0 }
    if len(l:servers) == 0
        call s:not_supported('Retrieving references')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/references',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \   'context': {'includeDeclaration': v:false},
            \ },
            \ 'on_notification': function('s:handle_location', [l:ctx, l:server, 'references']),
            \ })
    endfor

    echo 'Retrieving references ...'
endfunction

function! lsp#ui#vim#rename() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_rename_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Renaming')
        return
    endif

    let l:new_name = input('new name: ', expand('<cword>'))

    if empty(l:new_name)
        echo '... Renaming aborted ...'
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

    echo ' ... Renaming ...'
endfunction

function! lsp#ui#vim#document_format() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_formatting_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Document formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]
    call lsp#send_request(l:server, {
        \ 'method': 'textDocument/formatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'options': {
        \       'tabSize': getbufvar(bufnr('%'), '&tabstop'),
        \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
        \   },
        \ },
        \ 'on_notification': function('s:handle_text_edit', [l:server, s:last_req_id, 'document format']),
        \ })

    echo 'Formatting document ...'
endfunction

function! s:get_visual_selection_pos() abort
    " https://groups.google.com/d/msg/vim_dev/oCUQzO3y8XE/vfIMJiHCHtEJ
    " https://stackoverflow.com/a/6271254
    " getpos("'>'") doesn't give the right column so need to do extra processing
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return [0, 0, 0, 0]
    endif
    let lines[-1] = lines[-1][: column_end - (&selection ==# 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return [line_start, column_start, line_end, len(lines[-1])]
endfunction

function! lsp#ui#vim#document_range_format() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_range_formatting_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        call s:not_supported('Document range formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]

    let [l:start_lnum, l:start_col, l:end_lnum, l:end_col] = s:get_visual_selection_pos()
    call lsp#send_request(l:server, {
        \ 'method': 'textDocument/rangeFormatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'range': {
        \       'start': { 'line': l:start_lnum - 1, 'character': l:start_col - 1 },
        \       'end': { 'line': l:end_lnum - 1, 'character': l:end_col - 1 },
        \   },
        \   'options': {
        \       'tabSize': getbufvar(bufnr('%'), '&shiftwidth'),
        \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
        \   },
        \ },
        \ 'on_notification': function('s:handle_text_edit', [l:server, s:last_req_id, 'range format']),
        \ })

    echo 'Formatting document range ...'
endfunction

function! lsp#ui#vim#workspace_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving workspace symbols')
        return
    endif

    let l:query = input('query>')

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'workspace/symbol',
            \ 'params': {
            \   'query': l:query,
            \ },
            \ 'on_notification': function('s:handle_symbol', [l:server, s:last_req_id, 'workspaceSymbol']),
            \ })
    endfor

    echo 'Retrieving workspace symbols ...'
endfunction

function! lsp#ui#vim#document_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    let s:last_req_id = s:last_req_id + 1

    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving symbols')
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

    echo 'Retrieving document symbols ...'
endfunction

function! s:handle_symbol(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
        return
    endif

    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:data)

    call setqflist(l:list)

    if empty(l:list)
        call lsp#utils#error('No ' . a:type .' found')
    else
        echo 'Retrieved ' . a:type
        botright copen
    endif
endfunction

function! s:handle_location(ctx, server, type, data) abort "ctx = {counter, list, jump_if_one, last_req_id}
    if a:ctx['last_req_id'] != s:last_req_id
        return
    endif

    let a:ctx['counter'] = a:ctx['counter'] - 1

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
    else
        let a:ctx['list'] = a:ctx['list'] + lsp#ui#vim#utils#locations_to_loc_list(a:data)
    endif

    if a:ctx['counter'] == 0
        if empty(a:ctx['list'])
            call lsp#utils#error('No ' . a:type .' found')
        else
            if len(a:ctx['list']) == 1 && a:ctx['jump_if_one']
                normal! m'
                let l:loc = a:ctx['list'][0]
                let l:buffer = bufnr(l:loc['filename'])
                let l:cmd = l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . l:loc['filename']
                execute l:cmd . ' | call cursor('.l:loc['lnum'].','.l:loc['col'].')'
                redraw
            else
                call setqflist(a:ctx['list'])
                echo 'Retrieved ' . a:type
                botright copen
            endif
        endif
    endif
endfunction

function! s:handle_workspace_edit(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server)
        return
    endif

    call s:apply_workspace_edits(a:data['response']['result'])

    echo 'Renamed'
endfunction

function! s:handle_text_edit(server, last_req_id, type, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to '. a:type . ' for ' . a:server)
        return
    endif

    call s:apply_text_edits(a:data['request']['params']['textDocument']['uri'], a:data['response']['result'])

    echo 'Document formatted'
endfunction

" @params
"   workspace_edits - https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md#workspaceedit
function! s:apply_workspace_edits(workspace_edits) abort
    if has_key(a:workspace_edits, 'changes')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for [l:uri, l:text_edits] in items(a:workspace_edits['changes'])
            call s:apply_text_edits(l:uri, l:text_edits)
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    endif
    if has_key(a:workspace_edits, 'documentChanges')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for l:text_document_edit in a:workspace_edits['documentChanges']
            call s:apply_text_edits(l:text_document_edit['textDocument']['uri'], l:text_document_edit['edits'])
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    endif
endfunction

function! s:generate_move_cmd(line_pos, character_pos) abort
    let l:result = printf("%dG0", a:line_pos) " move the line and set to the cursor at the beggining
    if a:character_pos > 0
        let l:result .= printf("%dl", a:character_pos) " Move right until the character
    endif
    return l:result
endfunction

function! s:apply_text_edits(uri, text_edits) abort
    let l:path = lsp#utils#uri_to_path(a:uri)
    let l:buffer = bufnr(l:path)
    let l:cmd = 'keepjumps keepalt ' . (l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . l:path)
    for l:text_edit in a:text_edits
        let l:start_line = l:text_edit['range']['start']['line'] + 1
        let l:start_character = l:text_edit['range']['start']['character']
        let l:end_line = l:text_edit['range']['end']['line'] + 1
        let l:end_character = l:text_edit['range']['end']['character'] - 1  " -1 since the last character is excluded
        let l:new_text = l:text_edit['newText']
        let l:sub_cmd = s:generate_move_cmd(l:start_line, l:start_character) " move to the first position 
        let l:sub_cmd .= "v" " visual mode 
        let l:sub_cmd .= s:generate_move_cmd(l:end_line, l:end_character) " move to the last position 
        let l:sub_cmd .= printf("c%s", l:new_text) " change text
        let l:escaped_sub_cmd = substitute(l:sub_cmd, '''', '''''', 'g')
        let l:cmd = l:cmd . " | execute 'keepjumps normal! " . l:escaped_sub_cmd . "'"
    endfor
    call lsp#log('s:apply_text_edits', l:cmd)
    try
        set paste
        execute l:cmd
    finally
        set nopaste
    endtry
endfunction
