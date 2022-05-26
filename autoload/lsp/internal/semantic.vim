let s:use_vim_textprops = lsp#utils#_has_textprops() && !has('nvim')
let s:use_nvim_highlight = lsp#utils#_has_nvim_buf_highlight()
let s:textprop_cache = 'vim-lsp-semantic-cache'

if s:use_nvim_highlight
    let s:namespace_id = nvim_create_namespace('vim-lsp-semantic')
endif

" Global functions {{{1
function! lsp#internal#semantic#is_enabled() abort
    return g:lsp_semantic_enabled && (s:use_vim_textprops || s:use_nvim_highlight) ? v:true : v:false
endfunction

function! lsp#internal#semantic#_enable() abort
    if !lsp#internal#semantic#is_enabled() | return | endif

    augroup lsp#internal#semantic
        autocmd!
        au User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
    augroup END

    let l:events = [['User', 'lsp_buffer_enabled'], 'TextChanged', 'TextChangedI']
    if exists('##TextChangedP')
        call add(l:events, 'TextChangedP')
    endif
    let s:Dispose = lsp#callbag#pipe(
        \     lsp#callbag#fromEvent(l:events),
        \     lsp#callbag#filter({_->lsp#internal#semantic#is_enabled()}),
        \     lsp#callbag#debounceTime(g:lsp_semantic_delay),
        \     lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !~# '^(help\|terminal\|prompt\|popup)$'}),
        \     lsp#callbag#filter({_->!lsp#utils#is_large_window(win_getid())}),
        \     lsp#callbag#switchMap({_->
        \         lsp#callbag#pipe(
        \             s:semantic_request(),
        \             lsp#callbag#materialize(),
        \             lsp#callbag#filter({x->lsp#callbag#isNextNotification(x)}),
        \             lsp#callbag#map({x->x['value']})
        \         )
        \     }),
        \     lsp#callbag#subscribe({x->s:handle_semantic_request(x)})
        \ )
endfunction

function! lsp#internal#semantic#_disable() abort
    augroup lsp#internal#semantic
        autocmd!
    augroup END

    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! lsp#internal#semantic#get_legend(server) abort
    if !lsp#capabilities#has_semantic_tokens(a:server)
        return {'tokenTypes': [], 'tokenModifiers': []}
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)
    return l:capabilities['semanticTokensProvider']['legend']
endfunction

function! lsp#internal#semantic#get_provided_highlights() abort
    let l:capability = 'lsp#capabilities#has_semantic_tokens(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if empty(l:servers)
        return []
    endif

    let l:highlights = []
    for l:token_name in lsp#internal#semantic#get_legend(l:servers[0])['tokenTypes']
        call add(l:highlights, s:get_hl_name(l:token_name))
    endfor
    
    return l:highlights
endfunction

function! s:on_lsp_buffer_enabled() abort
    augroup lsp#internal#semantic
        if !exists('#BufUnload#<buffer>')
            execute 'au BufUnload <buffer> call setbufvar(' . bufnr() . ', ''lsp_semantic_previous_result_id'', '''')'
        endif
    augroup END
endfunction

function! s:supports_full_semantic_request(server) abort
    if !lsp#capabilities#has_semantic_tokens(a:server)
        return v:false
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)['semanticTokensProvider']
    if !has_key(l:capabilities, 'full')
        return v:false
    endif

    if type(l:capabilities['full']) ==# v:t_dict
        return v:true
    endif

    return l:capabilities['full']
endfunction

function! s:supports_delta_semantic_request(server) abort
    if !lsp#capabilities#has_semantic_tokens(a:server)
        return v:false
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)['semanticTokensProvider']
    if !has_key(l:capabilities, 'full')
        return v:false
    endif

    if type(l:capabilities['full']) !=# v:t_dict
        return v:false
    endif

    if !has_key(l:capabilities['full'], 'delta')
        return v:false
    endif

    return l:capabilities['full']['delta']
endfunction

function! s:get_server() abort
    let l:capability = 's:supports_delta_semantic_request(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)
    if empty(l:servers)
        let l:capability = 's:supports_full_semantic_request(v:val)'
        let l:servers = filter(lsp#get_allowed_servers(), l:capability)
    endif
    if empty(l:servers)
        return ''
    endif
    return l:servers[0]
endfunction

function! s:semantic_request() abort
    let l:server = s:get_server()
    if l:server ==# ''
        return lsp#callbag#empty()
    endif

    if (s:supports_delta_semantic_request(l:server)
        \ && getbufvar(bufnr(), 'lsp_semantic_previous_result_id') !=# '')
        return s:delta_semantic_request(l:server)
    else
        return s:full_semantic_request(l:server)
    endif
endfunction

function! s:full_semantic_request(server) abort
    return lsp#request(a:server, {
        \ 'method': 'textDocument/semanticTokens/full',
        \ 'params': {
        \     'textDocument': lsp#get_text_document_identifier()
        \ }})
endfunction

function! s:delta_semantic_request(server) abort
    return lsp#request(a:server, {
        \ 'method': 'textDocument/semanticTokens/full/delta',
        \ 'params': {
        \     'textDocument': lsp#get_text_document_identifier(),
        \     'previousResultId': getbufvar(bufname(), 'lsp_semantic_previous_result_id', 0)
        \ }})
endfunction

" Highlight helper functions {{{1
function! s:handle_semantic_request(data) abort
    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic highlight: response is invalid')
        return
    endif

    let l:server = a:data['server_name']
    let l:uri = a:data['request']['params']['textDocument']['uri']
    let l:path = lsp#utils#uri_to_path(l:uri)
    let l:bufnr = bufnr(l:path)

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(l:bufnr) | return | endif

    if has_key(a:data['response']['result'], 'data')
        call s:handle_semantic_tokens_response(l:server, l:bufnr, a:data['response']['result'])
    elseif has_key(a:data['response']['result'], 'edits')
        call s:handle_semantic_tokens_delta_response(l:server, l:bufnr, a:data['response']['result'])
    else
        " Don't update previous result ID if we could not update local copy
        call lsp#log('SemanticHighlight: unsupported semanticTokens method')
        return
    endif

    if has_key(a:data['response']['result'], 'resultId')
        call setbufvar(l:bufnr, 'lsp_semantic_previous_result_id', a:data['response']['result']['resultId'])
    endif
endfunction

function! s:handle_semantic_tokens_response(server, buf, result) abort
    call s:init_highlight(a:server, a:buf)

    call s:clear_highlights(a:server, a:buf)
    let l:highlights = {}
    for l:token in s:decode_tokens(a:result['data'])
        let l:highlights = s:add_highlight(l:highlights, a:server, a:buf, l:token)
    endfor
    call s:apply_highlights(l:highlights, a:buf)

    call setbufvar(a:buf, 'lsp_semantic_local_data', a:result['data'])
endfunction

function! s:startpos_compare(edit1, edit2) abort
    return a:edit1[0] == a:edit2[0] ? 0 : a:edit1[0] > a:edit2[0] ? -1 : 1
endfunction

function! s:handle_semantic_tokens_delta_response(server, buf, result) abort
    " The locations given in the edit are all referenced to the state before
    " any are applied and sorting is not required from the server,
    " therefore the edits must be sorted before applying.
    let l:edits = a:result['edits']
    call sort(l:edits, function('s:startpos_compare'))

    let l:localdata = getbufvar(a:buf, 'lsp_semantic_local_data')
    for l:edit in l:edits
        let l:insertdata = get(l:edit, 'data', [])
        let l:localdata = l:localdata[:l:edit['start'] - 1]
                      \ + l:insertdata
                      \ + l:localdata[l:edit['start'] + l:edit['deleteCount']:]
    endfor
    call setbufvar(a:buf, 'lsp_semantic_local_data', l:localdata)

    call s:clear_highlights(a:server, a:buf)
    let l:highlights = {}
    for l:token in s:decode_tokens(l:localdata)
        let l:highlights = s:add_highlight(l:highlights, a:server, a:buf, l:token)
    endfor
    call s:apply_highlights(l:highlights, a:buf)
endfunction

function! s:decode_tokens(data) abort
    let l:tokens = []

    let l:i = 0
    let l:line = 0
    let l:char = 0
    while l:i < len(a:data)
        let l:line = l:line + a:data[l:i]
        if a:data[l:i] > 0
            let l:char = 0
        endif
        let l:char = l:char + a:data[l:i + 1]

        call add(l:tokens, {
            \     'pos': {'line': l:line, 'character': l:char},
            \     'length': a:data[l:i + 2],
            \     'token_idx': a:data[l:i + 3],
            \     'token_modifiers': a:data[l:i + 4]
            \ })

        let l:i = l:i + 5
    endwhile

    return l:tokens
endfunction

function! s:init_highlight(server, buf) abort
    let l:legend = lsp#internal#semantic#get_legend(a:server)
    let l:highlight_groups = {
        \ 'LspType': 'Type',
        \ 'LspClass': 'Type',
        \ 'LspEnum': 'Type',
        \ 'LspInterface': 'TypeDef',
        \ 'LspStruct': 'Type',
        \ 'LspTypeParameter': 'Type',
        \ 'LspParameter': 'Identifier',
        \ 'LspVariable': 'Identifier',
        \ 'LspProperty': 'Identifier',
        \ 'LspEnumMember': 'Constant',
        \ 'LspEvents': 'Identifier',
        \ 'LspFunction': 'Function',
        \ 'LspMethod': 'Function',
        \ 'LspKeyword': 'Keyword',
        \ 'LspModifier': 'Type',
        \ 'LspComment': 'Comment',
        \ 'LspString': 'String',
        \ 'LspNumber': 'Number',
        \ 'LspRegexp': 'String',
        \ 'LspOperator': 'Operator'
    \ }

    for l:token_name in l:legend['tokenTypes']
        let l:hl_name = s:get_hl_name(l:token_name)
        if !index(keys(l:highlight_groups), l:hl_name)
            let l:highlight_groups[l:hl_name] = ''
        endif
    endfor

    for [l:key, l:value] in items(l:highlight_groups)
        if !hlexists(l:key)
            if l:value !=# ''
                exec 'highlight link' l:key l:value
            else
                exec 'highlight ' l:key 'gui=NONE cterm=NONE guifg=NONE ctermfg=NONE guibg=NONE ctermbg=NONE'
            endif
        endif
    endfor

    if s:use_vim_textprops
        for l:token_idx in range(len(l:legend['tokenTypes']))
            let l:token_name = l:legend['tokenTypes'][l:token_idx]
            let l:hl = s:get_hl_name(l:token_name)
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
    elseif s:use_nvim_highlight
        call nvim_buf_clear_namespace(a:buf, s:namespace_id, 0, line('$'))
    endif
endfunction

function! s:add_highlight(highlights, server, buf, token) abort
    let l:legend = lsp#internal#semantic#get_legend(a:server)
    let l:startpos = lsp#utils#position#lsp_to_vim(a:buf, a:token['pos'])
    let l:endpos = a:token['pos']
    let l:endpos['character'] = l:endpos['character'] + a:token['length']
    let l:endpos = lsp#utils#position#lsp_to_vim(a:buf, l:endpos)

    try
        if s:use_vim_textprops
            let l:textprop_name = s:get_textprop_name(a:server, a:token['token_idx'])
            let a:highlights[l:textprop_name] = get(a:highlights, l:textprop_name, [])
                                            \ + [[l:startpos[0], l:startpos[1], l:endpos[0], l:endpos[1]]]
        elseif s:use_nvim_highlight
            let l:char = a:token['pos']['character']
            let l:token_name = l:legend['tokenTypes'][a:token['token_idx']]
            call nvim_buf_add_highlight(a:buf, s:namespace_id, s:get_hl_name(a:server, l:token_name),
                                      \ l:startpos[0] - 1, l:startpos[1] - 1, l:endpos[1] - 1)
        endif
    catch
        call lsp#log('SemanticHighlight: error while adding prop on line ' . (l:startpos[0] + 1), v:exception)
    endtry

    return a:highlights
endfunction

function! s:apply_highlights(highlights, buf) abort
    if s:use_vim_textprops
        for [l:type, l:prop_list] in items(a:highlights)
            call prop_add_list({'type': l:type, 'bufnr': a:buf}, l:prop_list)
        endfor
    endif
endfunction

function! s:get_hl_name(token_name) abort
    return 'Lsp' . toupper(a:token_name[0]) . a:token_name[1:]
endfunction

function! s:get_textprop_name(server, token_idx) abort
    return 'vim-lsp-semantic-' . a:server . '-' . a:token_idx
endfunction

" vim: fdm=marker