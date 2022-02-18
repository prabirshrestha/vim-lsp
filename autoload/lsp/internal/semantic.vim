let s:use_vim_textprops = lsp#utils#_has_textprops() && !has('nvim')
let s:use_nvim_highlight = lsp#utils#_has_nvim_buf_highlight()
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

function! lsp#internal#semantic#_enable() abort
    if !lsp#internal#semantic#is_enabled() | return | endif

    let l:subscribed_events = ['FileType', 'TextChanged', 'TextChangedI']
    if has('popupwin')
        call add(l:subscribed_events, 'TextChangedP')
    endif

    " request and process full semantic tokens refresh when the filetype changes
    " or when the text is modified
    let s:Dispose = lsp#callbag#pipe(
        \     lsp#callbag#fromEvent(l:subscribed_events),
        \     lsp#callbag#filter({_->lsp#internal#semantic#is_enabled()}),
        \     lsp#callbag#debounceTime(g:lsp_semantic_delay),
        \     lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !~# '^(help\|terminal\|prompt\|popup)$'}),
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
        call add(l:tokens, {})

        let l:line = l:line + a:data[i]
        if a:data[i] > 0
            let l:char = 0
        endif
        let l:char = l:char + a:data[i + 1]

        let l:tokens[-1]['pos'] = {'line': l:line, 'character': l:char}
        let l:tokens[-1]['length'] = a:data[i + 2]
        let l:tokens[-1]['token_idx'] = a:data[i + 3]
        let l:tokens[-1]['token_modifiers'] = a:data[i + 4]

        let l:i = l:i + 5
    endwhile

    return l:tokens
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

" vim: fdm=marker
