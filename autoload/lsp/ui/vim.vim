function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
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

function! lsp#ui#vim#type_hierarchy() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_type_hierarchy_provider(v:val)')
    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        call s:not_supported('Retrieving type hierarchy')
        return
    endif
    let l:ctx = { 'counter': len(l:servers), 'list':[], 'last_command_id': l:command_id }
    " direction 0 children, 1 parent, 2 both
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/typeHierarchy',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': lsp#get_position(),
            \   'direction': 2,
            \   'resolve': 1,
            \ },
            \ 'on_notification': function('s:handle_type_hierarchy', [l:ctx, l:server, 'type hierarchy']),
            \ })
    endfor

    echo 'Retrieving type hierarchy ...'
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
    let l:servers = filter(lsp#get_whitelisted_servers(), l:capabilities_func)
    let l:command_id = lsp#_new_command()

    call setqflist([])

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
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_rename_prepare_provider(v:val)')
    let l:prepare_support = 1
    if len(l:servers) == 0
        let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_rename_provider(v:val)')
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

function! s:document_format(sync) abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_formatting_provider(v:val)')
    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        call s:not_supported('Document formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]
    redraw | echo 'Formatting document ...'
    call lsp#send_request(l:server, {
        \ 'method': 'textDocument/formatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'options': {
        \       'tabSize': getbufvar(bufnr('%'), '&tabstop'),
        \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
        \   },
        \ },
        \ 'sync': a:sync,
        \ 'on_notification': function('s:handle_text_edit', [l:server, l:command_id, 'document format']),
        \ })
endfunction

function! lsp#ui#vim#document_format_sync() abort
    let l:mode = mode()
    if l:mode =~# '[vV]' || l:mode ==# "\<C-V>"
        return s:document_format_range(1)
    endif
    return s:document_format(1)
endfunction

function! lsp#ui#vim#document_format() abort
    let l:mode = mode()
    if l:mode =~# '[vV]' || l:mode ==# "\<C-V>"
        return s:document_format_range(0)
    endif
    return s:document_format(0)
endfunction

function! lsp#ui#vim#stop_server(...) abort
    let l:name = get(a:000, 0, '')
    for l:server in lsp#get_whitelisted_servers()
        if !empty(l:name) && l:server != l:name
            continue
        endif
        echo 'Stopping' l:server 'server ...'
        call lsp#stop_server(l:server)
    endfor
endfunction

function! s:get_selection_pos(type) abort
    if a:type ==? 'v'
        let l:start_pos = getpos("'<")[1:2]
        let l:end_pos = getpos("'>")[1:2]
        " fix end_pos column (see :h getpos() and :h 'selection')
        let l:end_line = getline(l:end_pos[0])
        let l:offset = (&selection ==# 'inclusive' ? 1 : 2)
        let l:end_pos[1] = len(l:end_line[:l:end_pos[1]-l:offset])
        " edge case: single character selected with selection=exclusive
        if l:start_pos[0] == l:end_pos[0] && l:start_pos[1] > l:end_pos[1]
            let l:end_pos[1] = l:start_pos[1]
        endif
    elseif a:type ==? 'line'
        let l:start_pos = [line("'["), 1]
        let l:end_lnum = line("']")
        let l:end_pos = [line("']"), len(getline(l:end_lnum))]
    elseif a:type ==? 'char'
        let l:start_pos = getpos("'[")[1:2]
        let l:end_pos = getpos("']")[1:2]
    else
        let l:start_pos = [0, 0]
        let l:end_pos = [0, 0]
    endif

    return l:start_pos + l:end_pos
endfunction

function! s:document_format_range(sync, type) abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_range_formatting_provider(v:val)')
    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        call s:not_supported('Document range formatting')
        return
    endif

    " TODO: ask user to select server for formatting
    let l:server = l:servers[0]

    let [l:start_lnum, l:start_col, l:end_lnum, l:end_col] = s:get_selection_pos(a:type)
    let l:start_char = lsp#utils#to_char('%', l:start_lnum, l:start_col)
    let l:end_char = lsp#utils#to_char('%', l:end_lnum, l:end_col)
    redraw | echo 'Formatting document range ...'
    call lsp#send_request(l:server, {
        \ 'method': 'textDocument/rangeFormatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'range': {
        \       'start': { 'line': l:start_lnum - 1, 'character': l:start_char },
        \       'end': { 'line': l:end_lnum - 1, 'character': l:end_char },
        \   },
        \   'options': {
        \       'tabSize': getbufvar(bufnr('%'), '&shiftwidth'),
        \       'insertSpaces': getbufvar(bufnr('%'), '&expandtab') ? v:true : v:false,
        \   },
        \ },
        \ 'sync': a:sync,
        \ 'on_notification': function('s:handle_text_edit', [l:server, l:command_id, 'range format']),
        \ })
endfunction

function! lsp#ui#vim#document_range_format_sync() abort
    return s:document_format_range(1, visualmode())
endfunction

function! lsp#ui#vim#document_range_format() abort
    return s:document_format_range(0, visualmode())
endfunction

function! lsp#ui#vim#document_range_format_opfunc(type) abort
    return s:document_format_range(1, a:type)
endfunction

function! lsp#ui#vim#workspace_symbol() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let l:command_id = lsp#_new_command()

    call setqflist([])

    if len(l:servers) == 0
        call s:not_supported('Retrieving workspace symbols')
        return
    endif

    let l:query = inputdialog('query>', '', "\<ESC>")
    if l:query ==# "\<ESC>"
        return
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
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    let l:command_id = lsp#_new_command()

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

    call setqflist(l:list)

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
                call setqflist(a:ctx['list'])
                echo 'Retrieved ' . a:type
                botright copen
            else
                let l:lines = readfile(fnameescape(l:loc['filename']))
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

function! s:handle_type_hierarchy(ctx, server, type, data) abort "ctx = {counter, list, last_command_id}
    if a:ctx['last_command_id'] != lsp#_last_command()
        return
    endif

    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to '. a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
        return
    endif

    if empty(a:data['response']['result'])
        echo 'No type hierarchy found'
        return
    endif

    " Create new buffer in a split
    let l:position = 'topleft'
    let l:orientation = 'new'
    exec l:position . ' ' . 10 . l:orientation

    let l:provider = {
        \   'root': a:data['response']['result'],
        \   'root_state': 'expanded',
        \   'bufnr': bufnr('%'),
        \   'getChildren': function('s:get_children_for_tree_hierarchy'),
        \   'getParent': function('s:get_parent_for_tree_hierarchy'),
        \   'getTreeItem': function('s:get_treeitem_for_tree_hierarchy'),
        \ }

    call lsp#utils#tree#new(l:provider)

    echo 'Retrieved type hierarchy'
endfunction

function! s:hierarchyitem_to_treeitem(hierarchyitem) abort
    return {
        \ 'id': a:hierarchyitem,
        \ 'label': a:hierarchyitem['name'],
        \ 'command': function('s:hierarchy_treeitem_command', [a:hierarchyitem]),
        \ 'collapsibleState': has_key(a:hierarchyitem, 'parents') && !empty(a:hierarchyitem['parents']) ? 'expanded' : 'none',
        \ }
endfunction

function! s:hierarchy_treeitem_command(hierarchyitem) abort
    bwipeout
    call lsp#utils#tagstack#_update()
    call lsp#utils#location#_open_lsp_location(a:hierarchyitem)
endfunction

function! s:get_children_for_tree_hierarchy(Callback, ...) dict abort
    if a:0 == 0
        call a:Callback('success', [l:self['root']])
        return
    else
        call a:Callback('success', a:1['parents'])
    endif
endfunction

function! s:get_parent_for_tree_hierarchy(...) dict abort
    " TODO
endfunction

function! s:get_treeitem_for_tree_hierarchy(Callback, object) dict abort
    call a:Callback('success', s:hierarchyitem_to_treeitem(a:object))
endfunction

function! lsp#ui#vim#code_action() abort
    call lsp#ui#vim#code_action#do({
        \   'sync': v:false,
        \   'selection': v:false,
        \   'query_filter': v:false,
        \ })
endfunction
