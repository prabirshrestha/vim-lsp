let s:use_vim_textprops = has('textprop') && !has('nvim')
let s:use_nvim_highlight = exists('*nvim_buf_add_highlight') && has('nvim')
let s:textprop_cache = 'vim-lsp-semantic-cache'

if s:use_nvim_highlight
    let s:namespace_id = nvim_create_namespace('vim-lsp-semantic')
endif

if !hlexists('LspUnknownScope')
    highlight LspUnknownScope gui=NONE cterm=NONE guifg=NONE ctermfg=NONE guibg=NONE ctermbg=NONE
endif

" Global functions {{{1
function! lsp#ui#vim#semantic#is_enabled() abort
    return g:lsp_semantic_enabled && (s:use_vim_textprops || s:use_nvim_highlight) ? v:true : v:false
endfunction

function! lsp#ui#vim#semantic#get_scopes(server) abort
    if !lsp#capabilities#has_semantic_highlight(a:server)
        return []
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)
    return l:capabilities['semanticHighlighting']['scopes']
endfunction

function! lsp#ui#vim#semantic#handle_semantic(server, data) abort
    if !g:lsp_semantic_enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic highlight: response is invalid')
        return
    endif

    let l:uri = a:data['response']['params']['textDocument']['uri']
    let l:path = lsp#utils#uri_to_path(l:uri)
    let l:bufnr = bufnr(l:path)

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(l:bufnr) | return | endif

    call s:init_highlight(a:server, l:bufnr)

    for l:info in a:data['response']['params']['lines']
        let l:linenr = l:info['line']
        let l:tokens = has_key(l:info, 'tokens') ? l:info['tokens'] : ''
        call s:add_highlight(a:server, l:bufnr, l:linenr, l:tokens)
    endfor
endfunction

" Highlight helper functions {{{1
function! s:init_highlight(server, buf) abort
    if !empty(getbufvar(a:buf, 'lsp_did_semantic_setup'))
        return
    endif

    if s:use_vim_textprops
        let l:scopes = lsp#ui#vim#semantic#get_scopes(a:server)
        for l:scope_idx in range(len(l:scopes))
            let l:scope = l:scopes[l:scope_idx]
            let l:hl = s:get_hl_name(a:server, l:scope)

            silent! call prop_type_add(s:get_textprop_name(a:server, l:scope_idx), {'bufnr': a:buf, 'highlight': l:hl, 'combine': v:true})
        endfor

        silent! call prop_type_add(s:textprop_cache, {'bufnr': a:buf})
    endif

    call setbufvar(a:buf, 'lsp_did_semantic_setup', 1)
endfunction

function! s:hash(str) abort
    let l:hash = 1

    for l:char in split(a:str, '\zs')
        let l:hash = (l:hash * 31 + char2nr(l:char)) % 2147483647
    endfor

    return l:hash
endfunction

function! s:add_highlight(server, buf, line, tokens) abort
    " Return quickly if the tokens for this line are already set correctly,
    " according to the cached tokens.
    " This only works for Vim at the moment, for Neovim, we need extended
    " marks.
    if s:use_vim_textprops
        let l:props = filter(prop_list(a:line + 1, {'bufnr': a:buf}), {idx, prop -> prop['type'] ==# s:textprop_cache})
        let l:hash = s:hash(a:tokens)

        if !empty(l:props) && l:props[0]['id'] == l:hash
            " No changes for this line, so just return.
            return
        endif
    endif

    let l:scopes = lsp#ui#vim#semantic#get_scopes(a:server)
    let l:highlights = s:tokens_to_hl_info(a:tokens)

    if s:use_vim_textprops
        " Clear text properties from the previous run
        for l:scope_idx in range(len(l:scopes))
            call prop_remove({'bufnr': a:buf, 'type': s:get_textprop_name(a:server, l:scope_idx), 'all': v:true}, a:line + 1)
        endfor

        " Clear cache from previous run
        call prop_remove({'bufnr': a:buf, 'type': s:textprop_cache, 'all': v:true}, a:line + 1)

        " Add textprop for cache
        call prop_add(a:line + 1, 1, {'bufnr': a:buf, 'type': s:textprop_cache, 'id': l:hash})

        for l:highlight in l:highlights
            try
                call prop_add(a:line + 1, l:highlight['char'] + 1, { 'length': l:highlight['length'], 'bufnr': a:buf, 'type': s:get_textprop_name(a:server, l:highlight['scope'])})
            catch
                call lsp#log('SemanticHighlight: error while adding prop on line ' . (a:line + 1), v:exception)
            endtry
        endfor
    elseif s:use_nvim_highlight
        " Clear text properties from the previous run
        call nvim_buf_clear_namespace(a:buf, s:namespace_id, a:line, a:line + 1)

        for l:highlight in l:highlights
            call nvim_buf_add_highlight(a:buf, s:namespace_id, s:get_hl_name(a:server, l:scopes[l:highlight['scope']]), a:line, l:highlight['char'], l:highlight['char'] + l:highlight['length'])
        endfor
    endif
endfunction

function! s:get_hl_name(server, scope) abort
    let l:hl = 'LspUnknownScope'

    " Iterate over scopes in the order most general to most specific,
    " returning the last scope encountered. This is accomplished by a try
    " catch which ensures we always return the last scope even if an error is
    " encountered midway.
    try
        let l:info = lsp#get_server_info(a:server)
        let l:hl = l:info['semantic_highlight']
        let l:i = 0

        while (l:i < len(a:scope)) && has_key(l:hl, a:scope[l:i])
            let l:hl = l:hl[a:scope[l:i]]
            let l:i += 1
        endwhile
    catch
    endtry

    return type(l:hl) == type('') ? l:hl : 'LspUnknownScope'
endfunction

function! s:get_textprop_name(server, scope_index) abort
    return 'vim-lsp-semantic-' . a:server . '-' . a:scope_index
endfunction

" Response parsing functions {{{1

" Converts a list of bytes (MSB first) to a Number.
function! s:octets_to_number(octets) abort
    let l:ret = 0

    for l:octet in a:octets
        let l:ret *= 256
        let l:ret += l:octet
    endfor

    return l:ret
endfunction

function! s:tokens_to_hl_info(token) abort
    let l:ret = []
    let l:octets = lsp#utils#base64_decode(a:token)

    for l:i in range(0, len(l:octets) - 1, 8)
        let l:char = s:octets_to_number(l:octets[l:i : l:i+3])
        let l:length = s:octets_to_number(l:octets[l:i+4 : l:i+5])
        let l:scope = s:octets_to_number(l:octets[l:i+6 : l:i+7])

        call add(l:ret, { 'char': l:char, 'length': l:length, 'scope': l:scope })
    endfor

    return l:ret
endfunction

" Display scope tree {{{1
function! lsp#ui#vim#semantic#display_scope_tree(...) abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_semantic_highlight(v:val)')

    if len(l:servers) == 0
        call lsp#utils#error('Semantic highlighting not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]
    let l:info = lsp#get_server_info(l:server)
    let l:hl_mapping = get(l:info, 'semantic_highlight', {})
    let l:scopes = copy(lsp#ui#vim#semantic#get_scopes(l:server))

    " Convert scope array to tree
    let l:tree = {}

    for l:scope in l:scopes
        let l:cur = l:tree

        for l:scope_part in l:scope
            if !has_key(l:cur, l:scope_part)
                let l:cur[l:scope_part] = {}
            endif
            let l:cur = l:cur[l:scope_part]
        endfor
    endfor

    call s:display_tree(l:hl_mapping, l:tree, 0, a:0 > 0 ? a:1 - 1 : 20)
endfunction

function! s:display_tree(hl_tree, tree, indent, maxindent) abort
    for [l:item, l:rest] in sort(items(a:tree))
        if has_key(a:hl_tree, l:item) && type(a:hl_tree[l:item]) == type('')
            execute 'echohl ' . a:hl_tree[l:item]
        endif
        echo repeat(' ', 4 * a:indent) . l:item
        echohl None

        if a:indent < a:maxindent
            let l:new_hl_info = get(a:hl_tree, l:item, {})
            if type(l:new_hl_info) != type({})
                let l:new_hl_info = {}
            endif
            call s:display_tree(l:new_hl_info, l:rest, a:indent + 1, a:maxindent)
        endif
    endfor
endfunction

" vim: fdm=marker
