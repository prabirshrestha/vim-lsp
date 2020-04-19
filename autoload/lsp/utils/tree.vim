" This file is part of an installation of vim-yggdrasil, a vim/neovim tree viewer library.
" The source code of vim-yggdrasil is available at https://github.com/m-pilia/vim-yggdrasil
"
" vim-yggdrasil is free software, distributed under the MIT license.
" The full license is available at https://github.com/m-pilia/vim-yggdrasil/blob/master/LICENSE
"
" Yggdrasil version (git SHA-1): 043d0ab53dcdd0d91b7c7cd205791d64d4ed9624
"
" This installation was generated on 2020-03-15T14:47:27-0700 with the following vim command:
"     :YggdrasilPlant -plugin_dir=./ -namespace=lsp/utils

scriptencoding utf-8

" Callback to retrieve the tree item representation of an object.
function! s:node_get_tree_item_cb(node, object, status, tree_item) abort
    if a:status ==? 'success'
        let l:new_node = s:node_new(a:node.tree, a:object, a:tree_item, a:node)
        call add(a:node.children, l:new_node)
        call s:tree_render(l:new_node.tree)
    endif
endfunction

" Callback to retrieve the children objects of a node.
function! s:node_get_children_cb(node, status, childObjectList) abort
    for l:childObject in a:childObjectList
        let l:Callback = function('s:node_get_tree_item_cb', [a:node, l:childObject])
        call a:node.tree.provider.getTreeItem(l:Callback, l:childObject)
    endfor
endfunction

" Set the node to be collapsed or expanded.
"
" When {collapsed} evaluates to 0 the node is expanded, when it is 1 the node is
" collapsed, when it is equal to -1 the node is toggled (it is expanded if it
" was collapsed, and vice versa).
function! s:node_set_collapsed(collapsed) dict abort
    let l:self.collapsed = a:collapsed < 0 ? !l:self.collapsed : !!a:collapsed
endfunction

" Given a funcref {Condition}, return a list of all nodes in the subtree of
" {node} for which {Condition} evaluates to v:true.
function! s:search_subtree(node, Condition) abort
    if a:Condition(a:node)
        return [a:node]
    endif
    if len(a:node.children) < 1
        return []
    endif
    let l:result = []
    for l:child in a:node.children
        let l:result = l:result + s:search_subtree(l:child, a:Condition)
    endfor
    return l:result
endfunction

" Execute the action associated to a node
function! s:node_exec() dict abort
    if has_key(l:self.tree_item, 'command')
        call l:self.tree_item.command()
    endif
endfunction

" Return the depth level of the node in the tree. The level is defined
" recursively: the root has depth 0, and each node has depth equal to the depth
" of its parent increased by 1.
function! s:node_level() dict abort
    if l:self.parent == {}
        return 0
    endif
    return 1 + l:self.parent.level()
endf

" Return the string representation of the node. The {level} argument represents
" the depth level of the node in the tree and it is passed for convenience, to
" simplify the implementation and to avoid re-computing the depth.
function! s:node_render(level) dict abort
    let l:indent = repeat(' ', 2 * a:level)
    let l:mark = '• '

    if len(l:self.children) > 0 || l:self.lazy_open != v:false
        let l:mark = l:self.collapsed ? '▸ ' : '▾ '
    endif

    let l:label = split(l:self.tree_item.label, "\n")
    call extend(l:self.tree.index, map(range(len(l:label)), 'l:self'))

    let l:repr = l:indent . l:mark . l:label[0]
    \          . join(map(l:label[1:], {_, l -> "\n" . l:indent . '  ' . l}))

    let l:lines = [l:repr]
    if !l:self.collapsed
        if l:self.lazy_open
            let l:self.lazy_open = v:false
            let l:Callback = function('s:node_get_children_cb', [l:self])
            call l:self.tree.provider.getChildren(l:Callback, l:self.object)
        endif
        for l:child in l:self.children
            call add(l:lines, l:child.render(a:level + 1))
        endfor
    endif

    return join(l:lines, "\n")
endfunction

" Insert a new node in the tree, internally represented by a unique progressive
" integer identifier {id}. The node represents a certain {object} (children of
" {parent}) belonging to a given {tree}, having an associated action to be
" triggered on execution defined by the function object {exec}. If {collapsed}
" is true the node will be rendered as collapsed in the view. If {lazy_open} is
" true, the children of the node will be fetched when the node is expanded by
" the user.
function! s:node_new(tree, object, tree_item, parent) abort
    let a:tree.maxid += 1
    return {
    \ 'id': a:tree.maxid,
    \ 'tree': a:tree,
    \ 'object': a:object,
    \ 'tree_item': a:tree_item,
    \ 'parent': a:parent,
    \ 'collapsed': a:tree_item.collapsibleState ==? 'collapsed',
    \ 'lazy_open': a:tree_item.collapsibleState !=? 'none',
    \ 'children': [],
    \ 'level': function('s:node_level'),
    \ 'exec': function('s:node_exec'),
    \ 'set_collapsed': function('s:node_set_collapsed'),
    \ 'render': function('s:node_render'),
    \ }
endfunction

" Callback that sets the root node of a given {tree}, creating a new node
" with a {tree_item} representation for the given {object}. If {status} is
" equal to 'success', the root node is set and the tree view is updated
" accordingly, otherwise nothing happens.
function! s:tree_set_root_cb(tree, object, status, tree_item) abort
    if a:status ==? 'success'
        let a:tree.maxid = -1
        let a:tree.root = s:node_new(a:tree, a:object, a:tree_item, {})
        call s:tree_render(a:tree)
    endif
endfunction

" Return the node currently under the cursor from the given {tree}.
function! s:get_node_under_cursor(tree) abort
    let l:index = min([line('.'), len(a:tree.index) - 1])
    return a:tree.index[l:index]
endfunction

" Expand or collapse the node under cursor, and render the tree.
" Please refer to *s:node_set_collapsed()* for details about the
" arguments and behaviour.
function! s:tree_set_collapsed_under_cursor(collapsed) dict abort
    let l:node = s:get_node_under_cursor(l:self)
    call l:node.set_collapsed(a:collapsed)
    call s:tree_render(l:self)
endfunction

" Run the action associated to the node currently under the cursor.
function! s:tree_exec_node_under_cursor() dict abort
    call s:get_node_under_cursor(l:self).exec()
endfunction

" Render the {tree}. This will replace the content of the buffer with the
" tree view. Clear the index, setting it to a list containing a guard
" value for index 0 (line numbers are one-based).
function! s:tree_render(tree) abort
    if &filetype !=# 'lsp-tree'
        return
    endif

    let l:cursor = getpos('.')
    let a:tree.index = [-1]
    let l:text = a:tree.root.render(0)

    setlocal modifiable
    silent 1,$delete _
    silent 0put=l:text
    $d
    setlocal nomodifiable

    call setpos('.', l:cursor)
endfunction

" If {status} equals 'success', update all nodes of {tree} representing
" an {obect} with given {tree_item} representation.
function! s:node_update(tree, object, status, tree_item) abort
    if a:status !=? 'success'
        return
    endif
    for l:node in s:search_subtree(a:tree.root, {n -> n.object == a:object})
        let l:node.tree_item = a:tree_item
        let l:node.children = []
        let l:node.lazy_open = a:tree_item.collapsibleState !=? 'none'
    endfor
    call s:tree_render(a:tree)
endfunction

" Update the view if nodes have changed. If called with no arguments,
" update the whole tree. If called with an {object} as argument, update
" all the subtrees of nodes corresponding to {object}.
function! s:tree_update(...) dict abort
    if a:0 < 1
        call l:self.provider.getChildren({status, obj ->
        \   l:self.provider.getTreeItem(function('s:tree_set_root_cb', [l:self, obj[0]]), obj[0])})
    else
        call l:self.provider.getTreeItem(function('s:node_update', [l:self, a:1]), a:1)
    endif
endfunction

" Destroy the tree view. Wipe out the buffer containing it.
function! s:tree_wipe() dict abort
    execute 'bwipeout' . l:self.bufnr
endfunction

" Apply syntax to an lsp-tree buffer
function! s:filetype_syntax() abort
    syntax clear
    syntax match LspTreeMarkLeaf        "•" contained
    syntax match LspTreeMarkCollapsed   "▸" contained
    syntax match LspTreeMarkExpanded    "▾" contained
    syntax match LspTreeNode            "\v^(\s|[▸▾•])*.*"
    \      contains=LspTreeMarkLeaf,LspTreeMarkCollapsed,LspTreeMarkExpanded

    highlight def link LspTreeMarkLeaf        Type
    highlight def link LspTreeMarkExpanded    Type
    highlight def link LspTreeMarkCollapsed   Macro
endfunction

" Apply local settings to an lsp-tree buffer
function! s:filetype_settings() abort
    setlocal bufhidden=wipe
    setlocal buftype=nofile
    setlocal foldcolumn=0
    setlocal foldmethod=manual
    setlocal nobuflisted
    setlocal nofoldenable
    setlocal nohlsearch
    setlocal nolist
    setlocal nomodifiable
    setlocal nonumber
    setlocal nospell
    setlocal noswapfile
    setlocal nowrap

    nnoremap <silent> <buffer> <Plug>(lsp-tree-toggle-node)
        \ :call b:lsp_tree.set_collapsed_under_cursor(-1)<cr>

    nnoremap <silent> <buffer> <Plug>(lsp-tree-open-node)
        \ :call b:lsp_tree.set_collapsed_under_cursor(v:false)<cr>

    nnoremap <silent> <buffer> <Plug>(lsp-tree-close-node)
        \ :call b:lsp_tree.set_collapsed_under_cursor(v:true)<cr>

    nnoremap <silent> <buffer> <Plug>(lsp-tree-execute-node)
        \ :call b:lsp_tree.exec_node_under_cursor()<cr>

    nnoremap <silent> <buffer> <Plug>(lsp-tree-wipe-tree)
        \ :call b:lsp_tree.wipe()<cr>

    if !exists('g:lsp_tree_no_default_maps')
        nmap <silent> <buffer> o    <Plug>(lsp-tree-toggle-node)
        nmap <silent> <buffer> <cr> <Plug>(lsp-tree-execute-node)
        nmap <silent> <buffer> q    <Plug>(lsp-tree-wipe-tree)
    endif
endfunction

" Turns the current buffer into an lsp-tree tree view. Tree data is retrieved
" from the given {provider}, and the state of the tree is stored in a
" buffer-local variable called b:lsp_tree.
"
" The {bufnr} stores the buffer number of the view, {maxid} is the highest
" known internal identifier of the nodes. The {index} is a list that
" maps line numbers to nodes.
function! lsp#utils#tree#new(provider) abort
    let b:lsp_tree = {
    \ 'bufnr': bufnr('%'),
    \ 'maxid': -1,
    \ 'root': {},
    \ 'index': [],
    \ 'provider': a:provider,
    \ 'set_collapsed_under_cursor': function('s:tree_set_collapsed_under_cursor'),
    \ 'exec_node_under_cursor': function('s:tree_exec_node_under_cursor'),
    \ 'update': function('s:tree_update'),
    \ 'wipe': function('s:tree_wipe'),
    \ }

    augroup vim_lsp_tree
        autocmd!
        autocmd FileType lsp-tree call s:filetype_syntax() | call s:filetype_settings()
        autocmd BufEnter <buffer> call s:tree_render(b:lsp_tree)
    augroup END

    setlocal filetype=lsp-tree

    call b:lsp_tree.update()
endfunction
