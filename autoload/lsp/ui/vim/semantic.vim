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
    let l:servers = s:get_supported_servers()

    if len(l:servers) == 0
        call lsp#utils#error('Semantic tokens not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]

    " If there was previous request, use full/delta method.
    let l:previous_highlights = getbufvar(l:bufnr, 'previous_highlights')
    if type(l:previous_highlights) == type({}) && lsp#capabilities#has_semantic_tokens_delta(l:server)
        call lsp#send_request(l:server, {
        \   'method': 'textDocument/semanticTokens/full/delta',
        \   'params': {
        \       'textDocument': lsp#get_text_document_identifier(),
        \       'previousResultId': l:previous_highlights['result_id'],
        \   },
        \   'on_notification': function('s:handle_full_delta_semantic_highlight', [l:server, l:bufnr]),
        \ })
    else
        call lsp#send_request(l:server, {
        \   'method': 'textDocument/semanticTokens/full',
        \   'params': {
        \       'textDocument': lsp#get_text_document_identifier(),
        \   },
        \   'on_notification': function('s:handle_full_semantic_highlight', [l:server, l:bufnr]),
        \ })
    endif
endfunction

function! s:get_supported_servers() abort
    return filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_semantic_tokens(v:val)')
endfunction

function! s:parse_tokens_for_each_lines(legend, array)
    let l:num_data = len(a:array)
    if l:num_data % 5 != 0
        call lsp#log(printf('Skipping semantic token: invalid number of data (%d) returned', l:num_data))
        return {}
    endif

    let l:tokens_in_line = {}
    let l:current_line = 0
    let l:current_char = 0
    for l:idx in range(0, l:num_data - 1, 5)
        let l:delta_line = a:array[l:idx]
        let l:delta_start_char = a:array[l:idx + 1]
        let l:length = a:array[l:idx + 2]
        let l:token_type = a:array[l:idx + 3]
        " TODO: support token modifiers
        " let l:token_modifiers = a:array[l:idx + 4]

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

    return l:tokens_in_line
endfunction

function! s:handle_full_semantic_highlight(server, bufnr, data) abort
    if !g:lsp_semantic_enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic token: response is invalid')
        return
    endif

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(a:bufnr) | return | endif

    call s:init_highlight(a:server, a:bufnr)
    if type(a:data['response']) != type({})
    \   || !has_key(a:data['response'], 'result')
    \   || type(a:data['response']['result']) != type({})
    \       || !has_key(a:data['response']['result'], 'data')
    \       || type(a:data['response']['result']['data']) != type([])
        call lsp#log('Skipping semantic token: server returned nothing or invalid data')
        return
    endif

    let l:data = a:data['response']['result']['data']

    let l:legend = lsp#ui#vim#semantic#get_legend(a:server)
    let l:tokens_in_line = s:parse_tokens_for_each_lines(l:legend, l:data)

    " Save this result only if it has "resultId" parameter (i.e. supports
    " delta uploading). Save it to the buffer-local variable.
    if has_key(a:data['response']['result'], 'resultId')
        call setbufvar(a:bufnr, 'previous_highlights', {
        \   'result_id': a:data['response']['result']['resultId'],
        \   'raw': l:data,
        \ })
    endif

    for [l:line, l:tokens] in sort(items(l:tokens_in_line))
        " l:line is always string, conversion needed
        call s:add_highlight_for_line(a:server, a:bufnr, l:legend, str2nr(l:line), l:tokens)
    endfor
endfunction

function! s:handle_full_delta_semantic_highlight(server, bufnr, data) abort
    if !g:lsp_semantic_enabled | return | endif

    if lsp#client#is_error(a:data['response'])
        call lsp#log('Skipping semantic token: response is invalid')
        return
    endif

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(a:bufnr) | return | endif

    " Skip if previous token cannot be fetched
    let l:previous_highlights = getbufvar(a:bufnr, 'previous_highlights')
    if type(l:previous_highlights) != type({})
        call lsp#log('Skipping semantic token: failed to fetch previous highlights even if delta uploading was triggered')
        return
    endif

    call s:init_highlight(a:server, a:bufnr)

    if type(a:data['response']) != type({})
    \   || !has_key(a:data['response'], 'result')
    \   || type(a:data['response']['result']) != type({})
        call lsp#log('Skipping semantic token: server returned nothing or invalid response')
    endif

    " According to the LSP specification, SemanticTokens can be returned
    " instead of SemanticTokensDelta even if the method is '.../full/delta'.
    " Handle that case.
    if has_key(a:data['response']['result'], 'data')
        return s:handle_full_semantic_highlight(a:server, a:bufnr, a:data)
    endif

    if !has_key(a:data['response']['result'], 'edits')
    \  || type(a:data['response']['result']['edits']) != type([])
        call lsp#log('Skipping semantic token: server returned nothing or invalid edits')
        return
    endif

    let l:array = copy(l:previous_highlights['raw'])
    let l:prev_tokens_in_line = s:parse_tokens_for_each_lines(l:legend, l:array)

    let l:edits = a:data['response']['result']['edits']
    for l:edit in l:edits
        if type(l:edit) != type({}) || !has_key(l:edit, 'start') || !has_key(l:edit, 'deleteCount')
            call lsp#log('Skipping semantic token: invalid edit')
            return
        endif
        call remove(l:array, l:edit['start'], l:edit['start'] + l:edit['deleteCount'])
        if has_key(l:edit, 'data')
            call extend(l:array, l:edit['data'], l:edit['start'])
        endif
    endfor

    let l:legend = lsp#ui#vim#semantic#get_legend(a:server)
    let l:tokens_in_line = s:parse_tokens_for_each_lines(l:legend, l:array)

    " Save this result only if it has "resultId" parameter (i.e. supports
    " delta uploading). if there is not, remove the buffer variable
    if has_key(a:data['response']['result'], 'resultId')
        call setbufvar(a:bufnr, 'previous_highlights', {
        \   'result_id': a:data['response']['result']['resultId'],
        \   'raw': l:array,
        \ })
    else
        call setbufvar(a:bufnr, 'previous_highlights', '')
    endif

    " Replace changed lines only
    " TODO: it can be more effective to use relative position; adding newline
    " always triggers re-highlighting all lines under that line, but actually
    " it's not needed.
    for l:line in sort(keys(l:tokens_in_line))
        if l:prev_tokens_in_line[l:line] == l:tokens_in_line[l:line]
            continue
        endif

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
    let l:servers = s:get_supported_servers()

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

function! lsp#ui#vim#semantic#setup() abort
    augroup _lsp_semantic_tokens
        autocmd!
        autocmd BufEnter,CursorHold,CursorHoldI * if len(s:get_supported_servers()) > 0 | call lsp#ui#vim#semantic#do_semantic_highlight() | endif
    augroup END
endfunction

function! lsp#ui#vim#semantic#_disable() abort
    augroup _lsp_semantic_tokens
        autocmd!
    augroup END

    " TODO: remove all semantic highlighting --- but how?
endfunction

" vim: fdm=marker
