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
function! lsp#ui#vim#semantic#get_default_supported_token_types() abort
    return [
    \   'namespace',
    \   'type',
    \   'class',
    \   'enum',
    \   'interface',
    \   'struct',
    \   'typeParameter',
    \   'parameter',
    \   'variable',
    \   'property',
    \   'enumMember',
    \   'event',
    \   'function',
    \   'method',
    \   'macro',
    \   'keyword',
    \   'modifier',
    \   'comment',
    \   'string',
    \   'number',
    \   'regexp',
    \   'operator',
    \ ]
endfunction

function! lsp#ui#vim#semantic#get_default_supported_token_modifiers() abort
    " TODO: support these
    " return [
    " \   'declaration',
    " \   'definition',
    " \   'readonly',
    " \   'static',
    " \   'deprecated',
    " \   'abstract',
    " \   'async',
    " \   'modification',
    " \   'documentation',
    " \   'defaultLibrary',
    " \ ]
    return []
endfunction

function! lsp#ui#vim#semantic#is_enabled() abort
    return g:lsp_semantic_enabled && (s:use_vim_textprops || s:use_nvim_highlight) ? v:true : v:false
endfunction

function! lsp#ui#vim#semantic#get_legend(server) abort
    if !lsp#capabilities#has_semantic_tokens(a:server)
        return []
    endif

    let l:capabilities = lsp#get_server_capabilities(a:server)
    return l:capabilities['semanticTokensProvider']['legend']
endfunction

function! lsp#ui#vim#semantic#do_semantic_highlight() abort
    let l:bufnr = bufnr('%')
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_semantic_tokens(v:val)')

    if len(l:servers) == 0
        call lsp#utils#error('Semantic tokens not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]
    call lsp#send_request(l:server, {
    \   'method': 'textDocument/semanticTokens/full',
    \   'params': {
    \       'textDocument': lsp#get_text_document_identifier(),
    \   },
    \   'on_notification': function('s:handle_full_semantic_highlight', [l:server, l:bufnr]),
    \ })
endfunction

function! s:handle_full_semantic_highlight(server, bufnr, data) abort
    call lsp#log('semantic token: got semantic tokens!')
    if !g:lsp_semantic_enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic token: response is invalid')
        return
    endif

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(a:bufnr) | return | endif

    call s:init_highlight(a:server, a:bufnr)
    if type(a:data['response']) != type({}) || !has_key(a:data['response'], 'result') || type(a:data['response']['result']) != type({}) || !has_key(a:data['response']['result'], 'data') || type(a:data['response']['result']['data']) != type([])
        call lsp#log('Skipping semantic token: server returned nothing or invalid data')
        return
    endif

    call lsp#log('semantic tokens: do semantic highlighting')

    let l:data = a:data['response']['result']['data']
    let l:num_data = len(l:data)
    if l:num_data % 5 != 0
        call lsp#log(printf('Skipping semantic token: invalid number of data (%d) returned', l:num_data))
        return
    endif

    " Process highlights line by line.
    let l:tokens_in_line = {}
    let l:legend = lsp#ui#vim#semantic#get_legend(a:server)
    let l:current_line = 0
    let l:current_char = 0
    for l:idx in range(0, l:num_data - 1, 5)
        let l:delta_line = l:data[l:idx]
        let l:delta_start_char = l:data[l:idx + 1]
        let l:length = l:data[l:idx + 2]
        let l:token_type = l:data[l:idx + 3]
        " TODO: support token modifiers
        " let l:token_modifiers = l:data[l:idx + 4]

        " Calculate the absolute position from relative coordinates
        let l:line = l:current_line + l:delta_line
        let l:char = l:delta_line == 0 ? l:current_char + l:delta_start_char : l:delta_start_char
        let l:current_line = l:line
        let l:current_char = l:char

        if !has_key(l:tokens_in_line, l:line)
            let l:tokens_in_line[l:line] = []
        endif

        call add(l:tokens_in_line[l:line], {
        \   'start_char': l:char,
        \   'length': l:length,
        \   'token_type': l:token_type,
        \ })
    endfor

    for [l:line, l:tokens] in sort(items(l:tokens_in_line))
        " l:line is always string, conversion needed
        call s:add_highlight_for_line(a:server, a:bufnr, l:legend, str2nr(l:line), l:tokens)
    endfor
endfunction

function! s:init_highlight(server, buf) abort
    if !empty(getbufvar(a:buf, 'lsp_did_semantic_setup'))
        return
    endif

    if s:use_vim_textprops
        let l:token_types = lsp#ui#vim#semantic#get_legend(a:server)["tokenTypes"]
        for l:token_idx in range(len(l:token_types))
            let l:token_type = l:token_types[l:token_idx]
            let l:highlight = s:token_type_to_highlight(a:server, l:token_type)

            silent! call prop_type_add(s:get_textprop_name(a:server, l:token_idx), {'bufnr': a:buf, 'highlight': l:highlight, 'combine': v:true})
        endfor

        silent! call prop_type_add(s:textprop_cache, {'bufnr': a:buf})
    endif

    call setbufvar(a:buf, 'lsp_did_semantic_setup', 1)
endfunction

function! s:add_highlight_for_line(server, buf, legend, line, tokens) abort
    let l:token_types = a:legend['tokenTypes']

    " Debug {{{
    " let l:linestr = getbufline(a:buf, a:line + 1)[0]
    " for l:token in a:tokens
    "     let l:tokstr = strpart(l:linestr, l:token['start_char'], l:token['length'])
    "     call lsp#log(printf("colorize token '%s' @ %d:%d as '%s'", l:tokstr, a:line + 1, l:token['start_char'] + 1, l:token_types[l:token['token_type']]))
    " endfor
    "}}}

    if s:use_vim_textprops
        " Clear text properties from the previous run
        for l:token_idx in range(len(l:token_types))
            call prop_remove({'bufnr': a:buf, 'type': s:get_textprop_name(a:server, l:token_idx), 'all': v:true}, a:line + 1)
        endfor

        for l:token in a:tokens
            try
                call prop_add(a:line + 1, l:token['start_char'] + 1, { 'length': l:token['length'], 'bufnr': a:buf, 'type': s:get_textprop_name(a:server, l:token['token_type'])})
            catch
                call lsp#log('SemanticHighlight: error while adding prop on line ' . (a:line + 1), v:exception)
            endtry
        endfor
    elseif s:use_nvim_highlight
        " Clear text properties from the previous run
        call nvim_buf_clear_namespace(a:buf, s:namespace_id, a:line, a:line + 1)

        for l:token in a:tokens
            let l:highlight = s:token_type_to_highlight(a:server, l:token_types[l:token['token_type']])
            call nvim_buf_add_highlight(a:buf, s:namespace_id, l:highlight, a:line, l:token['start_char'], l:token['start_char'] + l:token['length'])
        endfor
    endif
endfunction

function! s:token_type_to_highlight(server, token_type) abort
    " Iterate over token_type in the order most general to most specific,
    " returning the last token_type encountered. This is accomplished by a try
    " catch which ensures we always return the last token_type even if an
    " error is encountered midway.
    try
        let l:info = lsp#get_server_info(a:server)
        let l:highlight = l:info['semantic_highlight']
        let l:i = 0

        if has_key(l:highlight, a:token_type)
            return l:highlight[a:token_type]
        endif
    catch
    endtry
    return 'LspUnknownScope'
endfunction

function! s:get_textprop_name(server, token_type_index) abort
    return 'vim-lsp-semantic-' . a:server . '-' . a:token_type_index
endfunction

function! lsp#ui#vim#semantic#display_token_types() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_semantic_tokens(v:val)')

    if len(l:servers) == 0
        call lsp#utils#error('Semantic tokens not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]
    let l:info = lsp#get_server_info(l:server)
    let l:highlight_mappings = get(l:info, 'semantic_highlight', {})
    let l:legend = lsp#ui#vim#semantic#get_legend(l:server)
    let l:token_types = uniq(sort(copy(l:legend['tokenTypes'])))

    for l:token_type in l:token_types
        if has_key(l:highlight_mappings, l:token_type)
            execute 'echohl ' . l:highlight_mappings[l:token_type]
        endif
        echo l:token_type
        echohl None
    endfor
endfunction

" vim: fdm=marker
