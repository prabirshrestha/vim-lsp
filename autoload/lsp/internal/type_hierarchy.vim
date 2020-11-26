function! lsp#internal#type_hierarchy#show() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_type_hierarchy_provider(v:val)')
    let l:command_id = lsp#_new_command()

    if len(l:servers) == 0
        return lsp#utils#error('Retrieving type hierarchy not supported for ' . &filetype)
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
