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

    let l:subscribed_events = ['FileType', 'TextChanged', 'TextChangedI']
    if exists('##TextChangedP')
        call add(l:subscribed_events, 'TextChangedP')
    endif

    " request and process full semantic tokens refresh when the filetype changes
    " or when the text is modified
    let s:Dispose = lsp#callbag#pipe(
        \     lsp#callbag#fromEvent(l:subscribed_events),
        \     lsp#callbag#filter({_->lsp#internal#semantic#is_enabled()}),
        \     lsp#callbag#debounceTime(g:lsp_semantic_delay),
        \     lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !~# '^(help\|terminal\|prompt\|popup)$'}),
        \     lsp#callbag#filter({_->!lsp#utils#is_large_window(win_getid())}),
        \     lsp#callbag#switchMap({_->
        \         lsp#callbag#pipe(
        \             s:send_full_semantic_request(),
        \             lsp#callbag#materialize(),
        \             lsp#callbag#filter({x->lsp#callbag#isNextNotification(x)}),
        \             lsp#callbag#map({x->x['value']})
        \         )
        \     }),
        \     lsp#callbag#subscribe({x->s:handle_semantic_request(x)})
        \ )
endfunction

function! lsp#internal#semantic#_disable() abort
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

function! s:send_full_semantic_request() abort
    let l:capability = 'lsp#capabilities#has_semantic_tokens(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if empty(l:servers)
        return lsp#callbag#empty()
    endif

    return lsp#request(l:servers[0], {
        \ 'method': 'textDocument/semanticTokens/full',
        \ 'params': {
        \     'textDocument': lsp#get_text_document_identifier()
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

    call s:init_highlight(l:server, l:bufnr)
    call s:clear_highlights(l:server, l:bufnr)

    for l:token in s:decode_tokens(a:data['response']['result']['data'])
        call s:add_highlight(l:server, l:bufnr, l:token)
    endfor
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
        \ 'LspClass': 'Class',
        \ 'LspEnum': 'Type',
        \ 'LspInterface': 'TypeDef',
        \ 'LspStruct': 'Type',
        \ 'LspTypeParameter': 'Type',
        \ 'LspParameter': 'Type',
        \ 'LspVariable': 'Identifier',
        \ 'LspProperty': 'TypeDef',
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
            if l:key != ''
                exec "highlight link" l:key l:value
            else
                exec "highlight " l:key "gui=NONE cterm=NONE guifg=NONE ctermfg=NONE guibg=NONE ctermbg=NONE"
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

function! s:add_highlight(server, buf, token) abort
    let l:legend = lsp#internal#semantic#get_legend(a:server)
    let l:startpos = lsp#utils#position#lsp_to_vim(a:buf, a:token['pos'])
    let l:endpos = a:token['pos']
    let l:endpos['character'] = l:endpos['character'] + a:token['length']
    let l:endpos = lsp#utils#position#lsp_to_vim(a:buf, l:endpos)

    try
        if s:use_vim_textprops
            let l:textprop_name = s:get_textprop_name(a:server, a:token['token_idx'])
            call prop_add(l:startpos[0], l:startpos[1],
                       \ {'length': l:endpos[1] - l:startpos[1], 'bufnr': a:buf, 'type': l:textprop_name})
        elseif s:use_nvim_highlight
            let l:char = a:token['pos']['character']
            let l:token_name = l:legend['tokenTypes'][a:token['token_idx']]
            call nvim_buf_add_highlight(a:buf, s:namespace_id, s:get_hl_name(a:server, l:token_name),
                                      \ l:startpos[0] - 1, l:startpos[1] - 1, l:endpos[1] - 1)
        endif
    catch
        call lsp#log('SemanticHighlight: error while adding prop on line ' . (a:token['line'] + 1), v:exception)
    endtry
endfunction

function! s:get_hl_name(token_name) abort
    return "Lsp" . toupper(a:token_name[0]) . a:token_name[1:]
endfunction

function! s:get_textprop_name(server, token_idx) abort
    return 'vim-lsp-semantic-' . a:server . '-' . a:token_idx
endfunction

" vim: fdm=marker
