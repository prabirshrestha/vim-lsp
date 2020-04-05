" vint: -ProhibitUnusedVariable

" constants {{{

let s:default_completion_item_kinds = {
            \ '1': 'text',
            \ '2': 'method',
            \ '3': 'function',
            \ '4': 'constructor',
            \ '5': 'field',
            \ '6': 'variable',
            \ '7': 'class',
            \ '8': 'interface',
            \ '9': 'module',
            \ '10': 'property',
            \ '11': 'unit',
            \ '12': 'value',
            \ '13': 'enum',
            \ '14': 'keyword',
            \ '15': 'snippet',
            \ '16': 'color',
            \ '17': 'file',
            \ '18': 'reference',
            \ '19': 'folder',
            \ '20': 'enum member',
            \ '21': 'constant',
            \ '22': 'struct',
            \ '23': 'event',
            \ '24': 'operator',
            \ '25': 'type parameter',
            \ }

let s:completion_item_kinds = {}

let s:completion_status_success = 'success'
let s:completion_status_failed = 'failed'
let s:completion_status_pending = 'pending'

let s:is_user_data_support = has('patch-8.0.1493')
let s:managed_user_data_key_base = 0
let s:managed_user_data_map = {}

" }}}

" completion state
let s:completion = {'counter': 0, 'status': '', 'matches': []}

function! lsp#omni#complete(findstart, base) abort
    let l:info = s:find_complete_servers()
    if empty(l:info['server_names'])
        return a:findstart ? -1 : []
    endif

    if a:findstart
        return col('.')
    else
        if !g:lsp_async_completion
            let s:completion['status'] = s:completion_status_pending
        endif

        " Find first item which has refresh_pattern
        let l:refresh_pattern = '\(\k\+$\)'
        for l:server_name in l:info['server_names']
            let l:server_info = lsp#get_server_info(l:server_name)
            if has_key (l:server_info, 'config') && has_key(l:server_info['config'], 'refresh_pattern')
                let l:refresh_pattern = l:server_info['config']['refresh_pattern']
                break
            endif
        endfor
        let l:curpos = getcurpos()
        let l:left = strpart(getline(l:curpos[1]), 0, l:curpos[2]-1)
        let s:completion['startcol'] = matchstrpos(l:left, l:refresh_pattern)[1]
        if s:completion['startcol'] == -1
            let s:completion['startcol'] = strlen(l:left)
        endif

        call s:send_completion_request(l:info)

        if g:lsp_async_completion
            " automatically call `s:display_completions` at `s:handle_omnicompletion` when retrieved textDocument/completion response.
            redraw
            return exists('v:none') ? v:none : []
        else
            " wait for retrieve textDocument/completion response and then call `s:display_completions` explicitly.
            while s:completion['status'] is# s:completion_status_pending && !complete_check()
                sleep 10m
            endwhile
            call timer_start(0, { timer -> s:display_completions(timer, l:info) })

            return exists('v:none') ? v:none : []
        endif
    endif
endfunction

function! s:get_filter_label(item) abort
    let l:user_data = lsp#omni#get_managed_user_data_from_completed_item(a:item)
    if has_key(l:user_data, 'completion_item') && has_key(l:user_data['completion_item'], 'filterText') && !empty(l:user_data['completion_item']['filterText'])
        return trim(l:user_data['completion_item']['filterText'])
    endif
    return trim(a:item['word'])
endfunction

function! s:prefix_filter(item, last_typed_word) abort
    let l:label = s:get_filter_label(a:item)

    if g:lsp_ignorecase
        return stridx(tolower(l:label), tolower(a:last_typed_word)) == 0
    else
        return stridx(l:label, a:last_typed_word) == 0
    endif
endfunction

function! s:contains_filter(item, last_typed_word) abort
    let l:label = s:get_filter_label(a:item)

    if g:lsp_ignorecase
        return stridx(tolower(l:label), tolower(a:last_typed_word)) >= 0
    else
        return stridx(l:label, a:last_typed_word) >= 0
    endif
endfunction

let s:pair = {
\  '"':  '"',
\  '''':  '''',
\  '{':  '}',
\  '(':  ')',
\  '[':  ']',
\}

function! s:display_completions(timer, info) abort
    " TODO: Allow multiple servers
    let l:server_name = a:info['server_names'][0]
    let l:server_info = lsp#get_server_info(l:server_name)

    let l:current_line = strpart(getline('.'), 0, col('.') - 1)
    let l:filter = has_key(l:server_info, 'config') && has_key(l:server_info['config'], 'filter') ? l:server_info['config']['filter'] : { 'name': 'prefix' }
    let l:last_typed_word = strpart(l:current_line, s:completion['startcol'])

    if l:filter['name'] ==? 'prefix'
        let s:completion['matches'] = filter(s:completion['matches'], {_, item -> s:prefix_filter(item, l:last_typed_word)})
	    if has_key(s:pair, l:last_typed_word[0])
            let [l:lhs, l:rhs] = [l:last_typed_word[0], s:pair[l:last_typed_word[0]]]
            for l:item in s:completion['matches']
                let l:str = l:item['word']
                if len(l:str) > 1 && l:str[0] ==# l:lhs && l:str[-1:] ==# l:rhs
                    let l:item['word'] = l:str[:-2]
                endif
            endfor
        endif
    elseif l:filter['name'] ==? 'contains'
        let s:completion['matches'] = filter(s:completion['matches'], {_, item -> s:contains_filter(item, l:last_typed_word)})
    endif

    let s:completion['status'] = ''

    if mode() is# 'i'
        call complete(s:completion['startcol'] + 1, s:completion['matches'])
    endif
endfunction

function! s:handle_omnicompletion(server_name, complete_counter, info, data) abort
    if s:completion['counter'] != a:complete_counter
        " ignore old completion results
        return
    endif

    if lsp#client#is_error(a:data) || !has_key(a:data, 'response') || !has_key(a:data['response'], 'result')
        let s:completion['status'] = s:completion_status_failed
        return
    endif

    let l:result = s:get_completion_result(a:server_name, a:data)
    let l:matches = l:result['matches']
    let s:completion['matches'] = l:matches
    let s:completion['status'] = s:completion_status_success

    if g:lsp_async_completion
        call s:display_completions(0, a:info)
    endif
endfunction

function! lsp#omni#get_kind_text(completion_item, ...) abort
    let l:server = get(a:, 1, '')
    if empty(l:server) " server name
        let l:completion_item_kinds = s:default_completion_item_kinds
    else
        if !has_key(s:completion_item_kinds, l:server)
            let l:server_info = lsp#get_server_info(l:server)
            if has_key (l:server_info, 'config') && has_key(l:server_info['config'], 'completion_item_kinds')
                let s:completion_item_kinds[l:server] = extend(copy(s:default_completion_item_kinds), l:server_info['config']['completion_item_kinds'])
            else
                let s:completion_item_kinds[l:server] = s:default_completion_item_kinds
            endif
        endif
        let l:completion_item_kinds = s:completion_item_kinds[l:server]
    endif

    return has_key(a:completion_item, 'kind') && has_key(l:completion_item_kinds, a:completion_item['kind'])
                \ ? l:completion_item_kinds[a:completion_item['kind']] : ''
endfunction

" auxiliary functions {{{

function! s:find_complete_servers() abort
    let l:server_names = []
    for l:server_name in lsp#get_whitelisted_servers()
        let l:init_capabilities = lsp#get_server_capabilities(l:server_name)
        if has_key(l:init_capabilities, 'completionProvider')
            " TODO: support triggerCharacters
            call add(l:server_names, l:server_name)
        endif
    endfor

    return { 'server_names': l:server_names }
endfunction

function! s:send_completion_request(info) abort
    let s:completion['counter'] = s:completion['counter'] + 1
    let l:server_name = a:info['server_names'][0]
    " TODO: support multiple servers
    call lsp#send_request(l:server_name, {
                \ 'method': 'textDocument/completion',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(),
                \   'position': lsp#get_position(),
                \ },
                \ 'on_notification': function('s:handle_omnicompletion', [l:server_name, s:completion['counter'], a:info]),
                \ })
endfunction

function! s:get_completion_result(server_name, data) abort
    let l:result = a:data['response']['result']

    if type(l:result) == type([])
        let l:items = l:result
        let l:incomplete = 0
    elseif type(l:result) == type({})
        let l:items = l:result['items']
        let l:incomplete = l:result['isIncomplete']
    else
        let l:items = []
        let l:incomplete = 0
    endif

    let l:matches = type(l:items) == type([]) ? map(l:items, {_, item -> lsp#omni#get_vim_completion_item(item, a:server_name) }) : []

    return {'matches': l:matches, 'incomplete': l:incomplete}
endfunction

function! lsp#omni#default_get_vim_completion_item(item, ...) abort
    let l:server_name = get(a:, 1, '')
    let l:complete_position = get(a:, 2, lsp#get_position())

    let l:word = ''
    if get(a:item, 'insertTextFormat', -1) == 2 && !empty(get(a:item, 'insertText', ''))
        " if candidate is snippet, use insertText. But it may include
        " placeholder.
        let l:word = lsp#utils#make_valid_word(a:item['insertText'])
    elseif !empty(get(a:item, 'insertText', ''))
        " if plain-text insertText, use it.
        let l:word = a:item['insertText']
    elseif has_key(a:item, 'textEdit')
        let l:word = lsp#utils#make_valid_word(a:item['label'])
    endif
    if !empty(l:word)
        let l:word = split(l:word, '\n')[0]
    endif
    if empty(l:word)
        let l:word = a:item['label']
    endif
    let l:abbr = a:item['label']

    if has_key(a:item, 'insertTextFormat') && a:item['insertTextFormat'] == 2
        let l:word = substitute(l:word, '\$[0-9]\+\|\${\%(\\.\|[^}]\)\+}', '', 'g')
    endif

    let l:completion = {
                \ 'word': lsp#utils#_trim(l:word),
                \ 'abbr': l:abbr,
                \ 'menu': '',
                \ 'info': '',
                \ 'icase': 1,
                \ 'dup': 1,
                \ 'empty': 1,
                \ 'kind': lsp#omni#get_kind_text(a:item, l:server_name)
                \ }

    " check support user_data.
    " if not support but g:lsp_text_edit_enabled enabled,
    " then print information to user and add information to log file.
    if !s:is_user_data_support && g:lsp_text_edit_enabled
        let l:no_support_error_message = 'textEdit support on omni complete requires Vim 8.0 patch 1493 or later(please check g:lsp_text_edit_enabled)'
        call lsp#utils#error(l:no_support_error_message)
        call lsp#log(l:no_support_error_message)
    endif

    " Add user_data.
    if s:is_user_data_support
        let l:completion['user_data'] = s:create_user_data(a:item, l:server_name, l:complete_position)
    endif

    if has_key(a:item, 'detail') && !empty(a:item['detail'])
        let l:completion['menu'] = substitute(a:item['detail'], '[ \t\n\r]\+', ' ', 'g')
    endif

    if has_key(a:item, 'documentation')
        if type(a:item['documentation']) == type('') " field is string
            let l:completion['info'] .= a:item['documentation']
        elseif type(a:item['documentation']) == type({}) &&
                    \ has_key(a:item['documentation'], 'value')
            " field is MarkupContent (hopefully 'plaintext')
            let l:completion['info'] .= substitute(a:item['documentation']['value'], '\r', '', 'g')
        endif
    endif

    return l:completion
endfunction

function! lsp#omni#get_vim_completion_item(...) abort
    return call(g:lsp_get_vim_completion_item[0], a:000)
endfunction

"
" Clear internal user_data map.
"
" This function should call at `CompleteDone` only if not empty `v:completed_item`.
"
function! lsp#omni#_clear_managed_user_data_map() abort
    let s:managed_user_data_key_base = 0
    let s:managed_user_data_map = {}
endfunction

"
" create item's user_data.
"
function! s:create_user_data(completion_item, server_name, complete_position) abort
    let l:user_data_key = '{"vim-lsp/key' . '":"' . string(s:managed_user_data_key_base) . '"}'
    let s:managed_user_data_map[l:user_data_key] = {
    \   'complete_position': a:complete_position,
    \   'server_name': a:server_name,
    \   'completion_item': a:completion_item
    \ }
    let s:managed_user_data_key_base += 1
    return l:user_data_key
endfunction

function! lsp#omni#get_managed_user_data_from_completed_item(completed_item) abort
    " the item has no user_data.
    if !has_key(a:completed_item, 'user_data')
        return {}
    endif

    " Check managed user_data.
    let l:user_data_key = get(a:completed_item, 'user_data', '')
    if !has_key(s:managed_user_data_map, l:user_data_key)
        return {}
    endif

    return s:managed_user_data_map[l:user_data_key]
endfunction

function! lsp#omni#get_completion_item_kinds() abort
    return map(keys(s:default_completion_item_kinds), {idx, key -> str2nr(key)})
endfunction

" }}}
