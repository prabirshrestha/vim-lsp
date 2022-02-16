let s:use_vim_textprops = lsp#utils#_has_textprops() && !has('nvim')
let s:use_nvim_highlight = exists('*nvim_buf_add_highlight') && has('nvim')
let s:textprop_cache = 'vim-lsp-semantic-cache'

if s:use_nvim_highlight
    let s:namespace_id = nvim_create_namespace('vim-lsp-semantic')
endif

if !hlexists('LspUnknownScope')
    highlight LspUnknownScope gui=NONE cterm=NONE guifg=NONE ctermfg=NONE guibg=NONE ctermbg=NONE
endif

" Global functions {{{1
function! lsp#internal#semantic#is_enabled() abort
    return g:lsp_semantic_enabled && (s:use_vim_textprops || s:use_nvim_highlight) ? v:true : v:false
endfunction

function! lsp#internal#semantic#get_legend(server) abort
    if !lsp#capabilities#has_semantic_tokens(a:server)
        return {'tokenTypes': [], 'tokenModifiers': []}
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)
    return l:capabilities['semanticTokensProvider']['legend']
endfunction

function! lsp#internal#semantic#semantic_full(server, buf, ...) abort
    if lsp#internal#semantic#is_enabled() && lsp#capabilities#has_semantic_tokens(a:server)
        call lsp#send_request(a:server, {
          \ 'method': 'textDocument/semanticTokens/full',
          \ 'params': {
          \     'textDocument': lsp#get_text_document_identifier(a:buf)
          \ },
          \ 'on_notification': function('s:handle_semantic_full', [a:server]),
          \ })
    else
        if !lsp#capabilities#has_semantic_tokens(a:server)
            call lsp#log_verbose(a:server..' does not support semantic tokens')
        endif
    endif
endfunction

" Highlight helper functions {{{1
function! s:handle_semantic_full(server, data) abort
    if !g:lsp_semantic_enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic highlight: response is invalid')
        return
    endif

    let l:uri = a:data['request']['params']['textDocument']['uri']
    let l:path = lsp#utils#uri_to_path(l:uri)
    let l:bufnr = bufnr(l:path)

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(l:bufnr) | return | endif

    call s:init_highlight(a:server, l:bufnr)
    call s:clear_highlights(a:server, l:bufnr)

    let l:linenr = 0
    let l:col = 0
    let l:result_data = a:data['response']['result']['data']
    while len(l:result_data) > 0
        let l:linenr = l:linenr + l:result_data[0]
        if l:result_data[0] > 0
            let l:col = 0
        endif
        let l:col = l:col + l:result_data[1]
        let l:length = l:result_data[2]
        let l:token_idx = l:result_data[3]
        let l:token_modifiers = l:result_data[4]

        call s:add_highlight(a:server, l:bufnr, l:linenr, l:col, l:length, l:token_idx, l:token_modifiers)

        let l:result_data = l:result_data[5:]
    endwhile
endfunction

function! s:init_highlight(server, buf) abort
    if s:use_vim_textprops
        let l:legend = lsp#internal#semantic#get_legend(a:server)
        for l:token_idx in range(len(l:legend['tokenTypes']))
            let l:token_name = l:legend['tokenTypes'][l:token_idx]
            let l:hl = s:get_hl_name(a:server, l:token_name)
            let l:textprop_name = s:get_textprop_name(a:server, l:token_idx)
            silent! call prop_type_add(l:textprop_name, {'bufnr': a:buf, 'highlight': l:hl, 'combine': v:true, 'priority': lsp#internal#textprop#priority('semantic')})
        endfor
    endif
endfunction

function! s:clear_highlights(server, buf) abort
    if s:use_vim_textprops
        let l:legend = lsp#internal#semantic#get_legend(a:server)
        for l:token_idx in range(len(l:legend['tokenTypes']))
            let l:textprop_name = s:get_textprop_name(a:server, l:token_idx)
            silent! call prop_remove({'bufnr': a:buf, 'type': l:textprop_name, 'all': v:true}, 1, line('$'))
        endfor
    endif
endfunction

function! s:add_highlight(server, buf, line, col, length, token_idx, token_modifiers) abort
    let l:legend = lsp#internal#semantic#get_legend(a:server)

    if s:use_vim_textprops
        try
            call prop_add(a:line + 1, a:col + 1, { 'length': a:length, 'bufnr': a:buf, 'type': s:get_textprop_name(a:server, a:token_idx)})
        catch
            call lsp#log('SemanticHighlight: error while adding prop on line ' . (a:line + 1), v:exception)
        endtry
    elseif s:use_nvim_highlight
        " Clear text properties from the previous run
        call nvim_buf_clear_namespace(a:buf, s:namespace_id, a:line, a:line + 1)

        for l:highlight in l:highlights
            let l:token_name = l:legend['tokenTypes'][token_idx]
            call nvim_buf_add_highlight(a:buf, s:namespace_id, s:get_hl_name(a:server, l:token_name), a:line, a:col, a:col + a:length)
        endfor
    endif
endfunction

function! s:get_hl_name(server, token_type) abort
    let l:hl = 'LspUnknownScope'
    let l:info = lsp#get_server_info(a:server)
    if has_key(l:info['semantic_highlight'], a:token_type)
        let l:hl = l:info['semantic_highlight'][a:token_type]
    endif

    return l:hl
endfunction

function! s:get_textprop_name(server, token_idx) abort
    return 'vim-lsp-semantic-' . a:server . '-' . a:token_idx
endfunction

" Display scope tree {{{1
function! lsp#internal#semantic#display_scope_tree(...) abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_semantic_highlight(v:val)')

    if len(l:servers) == 0
        call lsp#utils#error('Semantic highlighting not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]
    let l:info = lsp#get_server_info(l:server)
    let l:hl_mapping = get(l:info, 'semantic_highlight', {})
    let l:scopes = copy(lsp#internal#semantic#get_scopes(l:server))

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
