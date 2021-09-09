function! s:not_supported(what) abort
    return lsp#utils#error(printf("%s not supported for filetype '%s'", a:what, &filetype))
endfunction

function! lsp#ui#vim#implementation(in_preview, ...) abort
    let l:ctx = { 'in_preview': a:in_preview }
    if a:0
        let l:ctx['mods'] = a:1
    endif
    call s:list_location('implementation', l:ctx)
endfunction

function! lsp#ui#vim#type_definition(in_preview, ...) abort
    let l:ctx = { 'in_preview': a:in_preview }
    if a:0
        let l:ctx['mods'] = a:1
    endif
    call s:list_location('typeDefinition', l:ctx)
endfunction


function! lsp#ui#vim#declaration(in_preview, ...) abort
    let l:ctx = { 'in_preview': a:in_preview }
    if a:0
        let l:ctx['mods'] = a:1
    endif
    call s:list_location('declaration', l:ctx)
endfunction

function! lsp#ui#vim#definition(in_preview, ...) abort
    let l:ctx = { 'in_preview': a:in_preview }
    if a:0
        let l:ctx['mods'] = a:1
    endif
    call s:list_location('definition', l:ctx)
endfunction

function! lsp#ui#vim#references() abort
    let l:ctx = { 'jump_if_one': 0 }
    let l:request_params = { 'context': { 'includeDeclaration': v:false } }
    call s:list_location('references', l:ctx, l:request_params)
endfunction

function! s:list_location(method, ctx, ...) abort
    " typeDefinition => type definition
    let l:operation = substitute(a:method, '\u', ' \l\0', 'g')

    let l:capabilities_func = printf('lsp#capabilities#has_%s_provider(v:val)', substitute(l:operation, ' ', '_', 'g'))
    let l:servers = filter(lsp#get_allowed_servers(), l:capabilities_func)
    let l:command_id = lsp#_new_command()


    let l:ctx = extend({ 'counter': len(l:servers), 'list':[], 'last_command_id': l:command_id, 'jump_if_one': 1, 'mods': '', 'in_preview': 0 }, a:ctx)
    if len(l:servers) == 0
        call s:not_supported('Retrieving ' . l:operation)
        return
    endif

    let l:params = {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \ }
    if a:0
        call extend(l:params, a:1)
    endif
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/' . a:method,
            \ 'params': l:params,
            \ 'on_notification': function('s:handle_location', [l:ctx, l:server, l:operation]),
            \ })
    endfor

    echo printf('Retrieving %s ...', l:operation)
endfunction

function! s:rename(server, new_name, pos) abort
    if empty(a:new_name)
        echo '... Renaming aborted ...'
        return
    endif

    " needs to flush existing open buffers
    call lsp#send_request(a:server, {
        \ 'method': 'textDocument/rename',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': a:pos,
        \   'newName': a:new_name,
        \ },
        \ 'on_notification': function('s:handle_workspace_edit', [a:server, lsp#_last_command(), 'rename']),
        \ })

    echo ' ... Renaming ...'
endfunction

function! lsp#ui#vim#rename() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_rename_prepare_provider(v:val)')
    let l:prepare_support = 1
    if len(l:servers) == 0
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_rename_provider(v:val)')
        let l:prepare_support = 0
    endif

    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        call s:not_supported('Renaming')
        return
    endif

    " TODO: ask the user which server it should use to rename if there are multiple
    let l:server = l:servers[0]

    if l:prepare_support
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/prepareRename',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_rename_prepare', [l:server, l:command_id, 'rename_prepare']),
            \ })
        return
    endif

    call s:rename(l:server, input('new name: ', expand('<cword>')), lsp#get_position())
endfunction

function! lsp#ui#vim#stop_server(...) abort
    let l:name = get(a:000, 0, '')
    for l:server in lsp#get_allowed_servers()
        if !empty(l:name) && l:server != l:name
            continue
        endif
        echo 'Stopping' l:server 'server ...'
        call lsp#stop_server(l:server)
    endfor
endfunction

function! lsp#ui#vim#workspace_symbol(query) abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        call s:not_supported('Retrieving workspace symbols')
        return
    endif

    if !empty(a:query)
        let l:query = a:query
    else
        let l:query = inputdialog('query>', '', "\<ESC>")
        if l:query ==# "\<ESC>"
            return
        endif
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'workspace/symbol',
            \ 'params': {
            \   'query': l:query,
            \ },
            \ 'on_notification': function('s:handle_symbol', [l:server, l:command_id, 'workspaceSymbol']),
            \ })
    endfor

    redraw
    echo 'Retrieving workspace symbols ...'
endfunction

function! lsp#ui#vim#document_symbol() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    let l:command_id = lsp#_new_command()

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
            \ 'on_notification': function('s:handle_symbol', [l:server, l:command_id, 'documentSymbol']),
            \ })
    endfor

    echo 'Retrieving document symbols ...'
endfunction

function! s:handle_symbol(server, last_command_id, type, data) abort
    if a:last_command_id != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:server, a:data)

    if has('patch-8.2.2147')
      call setqflist(l:list)
      call setqflist([], 'a', {'title': a:type})
    else
      call setqflist([])
      call setqflist(l:list)
    endif

    if empty(l:list)
        call lsp#utils#error('No ' . a:type .' found')
    else
        echo 'Retrieved ' . a:type
        botright copen
    endif
endfunction

function! s:handle_location(ctx, server, type, data) abort "ctx = {counter, list, last_command_id, jump_if_one, mods, in_preview}
    if a:ctx['last_command_id'] != lsp#_last_command()
        return
    endif

    let a:ctx['counter'] = a:ctx['counter'] - 1

    if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
    else
        let a:ctx['list'] = a:ctx['list'] + lsp#utils#location#_lsp_to_vim_list(a:data['response']['result'])
    endif

    if a:ctx['counter'] == 0
        if empty(a:ctx['list'])
            call lsp#utils#error('No ' . a:type .' found')
        else
            call lsp#utils#tagstack#_update()

            let l:loc = a:ctx['list'][0]

            if len(a:ctx['list']) == 1 && a:ctx['jump_if_one'] && !a:ctx['in_preview']
                call lsp#utils#location#_open_vim_list_item(l:loc, a:ctx['mods'])
                echo 'Retrieved ' . a:type
                redraw
            elseif !a:ctx['in_preview']
                call setqflist([])
                call setqflist(a:ctx['list'])
                echo 'Retrieved ' . a:type
                botright copen
            else
                let l:lines = readfile(l:loc['filename'])
                if has_key(l:loc,'viewstart') " showing a locationLink
                    let l:view = l:lines[l:loc['viewstart'] : l:loc['viewend']]
                    call lsp#ui#vim#output#preview(a:server, l:view, {
                        \   'statusline': ' LSP Peek ' . a:type,
                        \   'filetype': &filetype
                        \ })
                else " showing a location
                    call lsp#ui#vim#output#preview(a:server, l:lines, {
                        \   'statusline': ' LSP Peek ' . a:type,
                        \   'cursor': { 'line': l:loc['lnum'], 'col': l:loc['col'], 'align': g:lsp_peek_alignment },
                        \   'filetype': &filetype
                        \ })
                endif
            endif
        endif
    endif
endfunction

function! s:handle_rename_prepare(server, last_command_id, type, data) abort
    if a:last_command_id != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    let l:range = a:data['response']['result']
    let l:lines = getline(1, '$')
    let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim('%', l:range['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim('%', l:range['end'])
    if l:start_line ==# l:end_line
        let l:name = l:lines[l:start_line - 1][l:start_col - 1 : l:end_col - 2]
    else
        let l:name = l:lines[l:start_line - 1][l:start_col - 1 :]
        for l:i in range(l:start_line, l:end_line - 2)
            let l:name .= "\n" . l:lines[l:i]
        endfor
        if l:end_col - 2 < 0
            let l:name .= "\n"
        else
            let l:name .= l:lines[l:end_line - 1][: l:end_col - 2]
        endif
    endif

    call timer_start(1, {x->s:rename(a:server, input('new name: ', l:name), l:range['start'])})
endfunction

function! s:handle_workspace_edit(server, last_command_id, type, data) abort
    if a:last_command_id != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    call lsp#utils#workspace_edit#apply_workspace_edit(a:data['response']['result'])

    echo 'Renamed'
endfunction

function! s:handle_text_edit(server, last_command_id, type, data) abort
    if a:last_command_id != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    call lsp#utils#text_edit#apply_text_edits(a:data['request']['params']['textDocument']['uri'], a:data['response']['result'])

    redraw | echo 'Document formatted'
endfunction

function! lsp#ui#vim#code_action() abort
    call lsp#ui#vim#code_action#do({
        \   'sync': v:false,
        \   'selection': v:false,
        \   'query': '',
        \ })
endfunction

function! lsp#ui#vim#code_lens() abort
    call lsp#ui#vim#code_lens#do({
        \   'sync': v:false,
        \ })
endfunction

function! lsp#ui#vim#add_tree_call_hierarchy_incoming() abort
    let l:ctx = { 'add_tree': v:true }
    call lsp#ui#vim#call_hierarchy_incoming(l:ctx)
endfunction

function! lsp#ui#vim#call_hierarchy_incoming(ctx) abort
    let l:ctx = extend({ 'method': 'incomingCalls', 'key': 'from' }, a:ctx)
    call s:prepare_call_hierarchy(l:ctx)
endfunction

function! lsp#ui#vim#call_hierarchy_outgoing() abort
    let l:ctx = { 'method': 'outgoingCalls', 'key': 'to' }
    call s:prepare_call_hierarchy(l:ctx)
endfunction

function! s:prepare_call_hierarchy(ctx) abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_call_hierarchy_provider(v:val)')
    let l:command_id = lsp#_new_command()

    let l:ctx = extend({ 'counter': len(l:servers), 'list':[], 'last_command_id': l:command_id }, a:ctx)
    if len(l:servers) == 0
        call s:not_supported('Retrieving call hierarchy')
        return
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/prepareCallHierarchy',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \ },
            \ 'on_notification': function('s:handle_prepare_call_hierarchy', [l:ctx, l:server, 'prepare_call_hierarchy']),
            \ })
    endfor

    echo 'Preparing call hierarchy ...'
endfunction

function! s:handle_prepare_call_hierarchy(ctx, server, type, data) abort
    if a:ctx['last_command_id'] != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
        call lsp#utils#error('Failed to '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    for l:item in a:data['response']['result']
        call s:call_hierarchy(a:ctx, a:server, l:item)
    endfor
endfunction

function! s:call_hierarchy(ctx, server, item) abort
    call lsp#send_request(a:server, {
        \ 'method': 'callHierarchy/' . a:ctx['method'],
        \ 'params': {
        \   'item': a:item,
        \ },
        \ 'on_notification': function('s:handle_call_hierarchy', [a:ctx, a:server, 'call_hierarchy']),
        \ })
endfunction

function! s:handle_call_hierarchy(ctx, server, type, data) abort
    if a:ctx['last_command_id'] != lsp#_last_command()
        return
    endif

    let a:ctx['counter'] = a:ctx['counter'] - 1

    if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
        call lsp#utils#error('Failed to retrieve '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
    elseif a:data['response']['result'] isnot v:null
        for l:item in a:data['response']['result']
            let l:loc = s:hierarchy_item_to_vim(l:item[a:ctx['key']], a:server)
            if l:loc isnot v:null
                let a:ctx['list'] += [l:loc]
            endif
        endfor
    endif

    if a:ctx['counter'] == 0
        if empty(a:ctx['list'])
            call lsp#utils#error('No ' . a:type .' found')
        else
            call lsp#utils#tagstack#_update()
            if get(a:ctx, 'add_tree', v:false)
                let l:qf = getqflist({'idx' : 0, 'items': []})
                let l:pos = l:qf.idx
                let l:parent = l:qf.items
                let l:level = count(l:parent[l:pos-1].text, g:lsp_tree_incoming_prefix)
                let a:ctx['list'] = extend(l:parent, map(a:ctx['list'], 'extend(v:val, {"text": repeat("' . g:lsp_tree_incoming_prefix . '", l:level+1) . v:val.text})'), l:pos)
            endif
            call setqflist([])
            call setqflist(a:ctx['list'])
            echo 'Retrieved ' . a:type
            botright copen
            if get(a:ctx, 'add_tree', v:false)
                " move the cursor to the newly added item
                execute l:pos + 1
            endif
        endif
    endif
endfunction

function! s:hierarchy_item_to_vim(item, server) abort
    let l:uri = a:item['uri']
    if !lsp#utils#is_file_uri(l:uri)
        return v:null
    endif

    let l:path = lsp#utils#uri_to_path(l:uri)
    let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, a:item['range']['start'])
    let l:text = '[' . lsp#ui#vim#utils#_get_symbol_text_from_kind(a:server, a:item['kind']) . '] ' . a:item['name']
    if has_key(a:item, 'detail')
        let l:text .= ": " . a:item['detail']
    endif

    return {
        \ 'filename': l:path,
        \ 'lnum': l:line,
        \ 'col': l:col,
        \ 'text': l:text,
        \ }
endfunction
