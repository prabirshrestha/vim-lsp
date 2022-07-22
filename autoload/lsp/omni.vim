" vint: -ProhibitUnusedVariable

" constants {{{
let s:t_dict = type({})

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

        let l:left = strpart(getline('.'), 0, col('.')-1)

        " Initialize the default startcol. It will be updated if the completion items has textEdit.
        let s:completion['startcol'] = s:get_startcol(l:left, l:info['server_names'])

        " The `l:info` variable will be filled with completion results after request was finished.
        call s:send_completion_request(l:info)

        if g:lsp_async_completion
            " If g:lsp_async_completion == v:true, the `s:display_completions` " will be called by `s:send_completion_request`.
            redraw
            return exists('v:none') ? v:none : []
        else
            " Wait for finished the textDocument/completion request and then call `s:display_completions` explicitly.
            call lsp#utils#_wait(-1, {-> s:completion['status'] isnot# s:completion_status_pending || complete_check()}, 10)
            call timer_start(0, { timer -> s:display_completions(timer, l:info) })

            return exists('v:none') ? v:none : []
        endif
    endif
endfunction

function! s:get_filter_label(item) abort
    return lsp#utils#_trim(a:item['word'])
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
    let l:last_typed_word = strpart(l:current_line, s:completion['startcol'] - 1)

    let l:filter = has_key(l:server_info, 'config') && has_key(l:server_info['config'], 'filter') ? l:server_info['config']['filter'] : { 'name': 'prefix' }
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
        call complete(s:completion['startcol'], s:completion['matches'])
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
    let s:completion['matches'] = l:result['items']
    let s:completion['startcol'] = min([l:result['startcol'], s:completion['startcol']])
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

function! s:get_kind_text_mappings(server) abort
	let l:server_name = a:server['name']
	if has_key(s:completion_item_kinds, l:server_name)
		return s:completion_item_kinds[l:server_name]
	else
		if has_key(a:server, 'config') && has_key(a:server['config'], 'completion_item_kinds')
			let s:completion_item_kinds[l:server_name] = extend(copy(s:default_completion_item_kinds), a:server['config']['completion_item_kinds'])
		else
			let s:completion_item_kinds[l:server_name] = s:default_completion_item_kinds
		endif
		return s:completion_item_kinds[l:server_name]
	endif
endfunction

" auxiliary functions {{{

function! s:find_complete_servers() abort
    let l:server_names = []
    for l:server_name in lsp#get_allowed_servers()
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
        \   'context': { 'triggerKind': 1 },
        \ },
        \ 'on_notification': function('s:handle_omnicompletion', [l:server_name, s:completion['counter'], a:info]),
        \ })
endfunction

function! s:get_completion_result(server_name, data) abort
    let l:result = a:data['response']['result']

    let l:options = {
        \ 'server': lsp#get_server_info(a:server_name),
        \ 'position': lsp#get_position(),
        \ 'response': a:data['response'],
        \ }

    return lsp#omni#get_vim_completion_items(l:options)
endfunction

function! s:sort_by_sorttext(i1, i2) abort
    let l:text1 = get(a:i1, 'sortText')
    let l:text2 = get(a:i2, 'sortText')

    " sortText is possibly empty string
    let l:text1 = !empty(l:text1) ? l:text1 : a:i1['label']
    let l:text2 = !empty(l:text2) ? l:text2 : a:i2['label']

    if g:lsp_ignorecase
        return l:text1 ==? l:text2 ? 0 : l:text1 >? l:text2 ? 1 : -1
    else
        return l:text1 ==# l:text2 ? 0 : l:text1 ># l:text2 ? 1 : -1
    endif
endfunction

" Create vim's completed items from LSP response.
"
" options = {
"   server: {}, " needs to be server_info and not server_name
"   position: lsp#get_position(),
"   response: {}, " needs to be the entire lsp response. errors need to be
"   handled before calling the fuction
" }
"
" * The returned` startcol` may be the same as the cursor position, in which case you need to decide which one to use.
"
" @return { 'items': v:completed_item[], 'incomplete': v:t_bool, 'startcol': number }
"
function! lsp#omni#get_vim_completion_items(options) abort
    let l:server = a:options['server']
    let l:server_name = l:server['name']
    let l:kind_text_mappings = s:get_kind_text_mappings(l:server)
    let l:complete_position = a:options['position']
    let l:current_line = getline('.')
    let l:default_startcol = s:get_startcol(strcharpart(l:current_line, 0, l:complete_position['character']), [l:server_name])
    let l:default_start_character = strchars(strpart(l:current_line, 0, l:default_startcol - 1))
    let l:refresh_pattern = s:get_refresh_pattern([l:server_name])

    let l:result = a:options['response']['result']
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

    let l:sort = has_key(l:server, 'config') && has_key(l:server['config'], 'sort') ? l:server['config']['sort'] : v:null

    if len(l:items) > 0 && type(l:sort) == s:t_dict && len(l:items) <= l:sort['max']
      " If first item contains sortText, maybe we can use sortText
      call sort(l:items, function('s:sort_by_sorttext'))
    endif

    let l:start_character = l:complete_position['character']

    let l:start_characters = [] " The mapping of item specific start_character.
    let l:vim_complete_items = []
    for l:completion_item in l:items
        let l:expandable = get(l:completion_item, 'insertTextFormat', 1) == 2
        let l:vim_complete_item = {
            \ 'kind': get(l:kind_text_mappings, get(l:completion_item, 'kind', '') , ''),
            \ 'dup': 1,
            \ 'empty': 1,
            \ 'icase': 1,
            \ }
        let l:range = lsp#utils#text_edit#get_range(get(l:completion_item, 'textEdit', {}))
        if has_key(l:completion_item, 'textEdit') && type(l:completion_item['textEdit']) == s:t_dict && !empty(l:range) && has_key(l:completion_item['textEdit'], 'newText')
            let l:text_edit_new_text = l:completion_item['textEdit']['newText']
            if has_key(l:completion_item, 'filterText') && !empty(l:completion_item['filterText']) && matchstr(l:text_edit_new_text, '^' . l:refresh_pattern) ==# ''
                " Use filterText as word.
                let l:vim_complete_item['word'] = l:completion_item['filterText']
            else
                " Use textEdit.newText as word.
                let l:vim_complete_item['word'] = l:text_edit_new_text
            endif

            " Fix overlapped text if needed.
            let l:item_start_character = l:range['start']['character']
            if l:item_start_character < l:default_start_character
                " Add already typed word. The typescript-language-server returns `[Symbol]` item for the line of `Hoo.|`. So we should add `.` (`.[Symbol]`) .
                let l:overlap_text = strcharpart(l:current_line, l:item_start_character, l:default_start_character - l:item_start_character)
                if stridx(l:vim_complete_item['word'], l:overlap_text) != 0
                    let l:vim_complete_item['word'] = l:overlap_text . l:vim_complete_item['word']
                endif
            endif
            let l:start_character = min([l:item_start_character, l:start_character])
            let l:start_characters += [l:item_start_character]
        elseif has_key(l:completion_item, 'insertText') && !empty(l:completion_item['insertText'])
            let l:vim_complete_item['word'] = l:completion_item['insertText']
            let l:start_characters += [l:default_start_character]
        else
            let l:vim_complete_item['word'] = l:completion_item['label']
            let l:start_characters += [l:default_start_character]
        endif

        if l:expandable
            let l:vim_complete_item['word'] = lsp#utils#make_valid_word(substitute(l:vim_complete_item['word'], '\$[0-9]\+\|\${\%(\\.\|[^}]\)\+}', '', 'g'))
            let l:vim_complete_item['abbr'] = l:completion_item['label'] . '~'
        else
            let l:vim_complete_item['abbr'] = l:completion_item['label']
        endif

        if s:is_user_data_support
            let l:vim_complete_item['user_data'] = s:create_user_data(l:completion_item, l:server_name, l:complete_position, l:start_characters[len(l:start_characters) - 1])
        endif

        let l:vim_complete_items += [l:vim_complete_item]
    endfor

    " Add the additional text for startcol correction.
    if l:start_character != l:default_start_character
        for l:i in range(len(l:start_characters))
            let l:item_start_character = l:start_characters[l:i]
            if l:start_character < l:item_start_character
                let l:item = l:vim_complete_items[l:i]
                let l:item['word'] = strcharpart(l:current_line, l:start_character, l:item_start_character - l:start_character) . l:item['word']
            endif
        endfor
    endif
    let l:startcol = lsp#utils#position#lsp_character_to_vim('%', { 'line': l:complete_position['line'], 'character': l:start_character })

    return { 'items': l:vim_complete_items, 'incomplete': l:incomplete, 'startcol': l:startcol }
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
function! s:create_user_data(completion_item, server_name, complete_position, start_character) abort
    let l:user_data_key = s:create_user_data_key(s:managed_user_data_key_base)
    let s:managed_user_data_map[l:user_data_key] = {
    \   'complete_position': a:complete_position,
    \   'server_name': a:server_name,
    \   'completion_item': a:completion_item,
    \   'start_character': a:start_character,
    \ }
    let s:managed_user_data_key_base += 1
    return l:user_data_key
endfunction

function! lsp#omni#get_managed_user_data_from_completed_item(completed_item) abort
    " the item has no user_data.
    if !has_key(a:completed_item, 'user_data')
        return {}
    endif

    let l:user_data_string = get(a:completed_item, 'user_data', '')
    if type(l:user_data_string) != type('')
        return {}
    endif

    " Check managed user_data.
    if has_key(s:managed_user_data_map, l:user_data_string)
        return s:managed_user_data_map[l:user_data_string]
    endif

    " Check json.
    if stridx(l:user_data_string, '"vim-lsp/key"') != -1
        try
            let l:user_data = json_decode(l:user_data_string)
            if has_key(l:user_data, 'vim-lsp/key')
                let l:user_data_key = s:create_user_data_key(l:user_data['vim-lsp/key'])
                if has_key(s:managed_user_data_map, l:user_data_key)
                    return s:managed_user_data_map[l:user_data_key]
                endif
            endif
        catch /.*/
        endtry
    endif
    return {}
endfunction

function! lsp#omni#get_completion_item_kinds() abort
    return map(keys(s:default_completion_item_kinds), {idx, key -> str2nr(key)})
endfunction

function! s:create_user_data_key(base) abort
    return '{"vim-lsp/key":"' . a:base . '"}'
endfunction

function! s:get_startcol(left, server_names) abort
    " Initialize the default startcol. It will be updated if the completion items has textEdit.
    let l:startcol = 1 + matchstrpos(a:left, s:get_refresh_pattern(a:server_names))[1]
    return l:startcol == 0 ? strlen(a:left) + 1 : l:startcol
endfunction

function! s:get_refresh_pattern(server_names) abort
    for l:server_name in a:server_names
        let l:server_info = lsp#get_server_info(l:server_name)
        if has_key(l:server_info, 'config') && has_key(l:server_info['config'], 'refresh_pattern')
            return l:server_info['config']['refresh_pattern']
        endif
    endfor
    return '\(\k\+$\)'
endfunction

" }}}
