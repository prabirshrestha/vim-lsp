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
let s:user_data_key = 'vim-lsp/textEdit'
let s:user_data_additional_edits_key = 'vim-lsp/additionalTextEdits'
let s:user_data_insert_start_key = 'vim-lsp/insertStart'
let s:user_data_filtertext_key = 'vim-lsp/filterText'

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

        call s:send_completion_request(l:info)

        if g:lsp_async_completion
            redraw
            return exists('v:none') ? v:none : []
        else
            while s:completion['status'] is# s:completion_status_pending && !complete_check()
                sleep 10m
            endwhile

            " TODO: Allow multiple servers
            let l:server_name = l:info['server_names'][0]
            let l:server_info = lsp#get_server_info(l:server_name)

            let l:typed_pattern = has_key(l:server_info, 'config') && has_key(l:server_info['config'], 'typed_pattern') ? l:server_info['config']['typed_pattern'] : '\k*$'
            let l:current_line = strpart(getline('.'), 0, col('.') - 1)

            let s:start_pos = min(map(copy(s:completion['matches']), {_, item -> s:get_insertion_point(item, l:current_line, l:typed_pattern) }))

            let l:filter = has_key(l:server_info, 'config') && has_key(l:server_info['config'], 'filter') ? l:server_info['config']['filter'] : { 'name': 'none' }
            let l:last_typed_word = strpart(l:current_line, s:start_pos)

            if l:filter['name'] ==? 'prefix'
                let s:completion['matches'] = filter(s:completion['matches'], {_, item -> s:prefix_filter(item, l:last_typed_word)})
            elseif l:filter['name'] ==? 'contains'
                let s:completion['matches'] = filter(s:completion['matches'], {_, item -> s:contains_filter(item, l:last_typed_word)})
            endif

            let s:completion['status'] = ''

            call timer_start(0, function('s:display_completions'))

            return exists('v:none') ? v:none : []
        endif
    endif
endfunction

function! s:get_insertion_point(item, current_line, typed_pattern) abort
    if !has_key(a:item, 'user_data')
        let l:insert_start = -1
    else
        let l:insert_start = get(json_decode(a:item['user_data']), s:user_data_insert_start_key, -1)
    endif

    if l:insert_start >= 0
        return l:insert_start
    else
        return match(a:current_line, a:typed_pattern)
    endif
endfunction

function! s:get_filter_label(item) abort
    if !has_key(a:item, 'user_data')
        return trim(a:item['word'])
    endif

    let l:user_data = json_decode(a:item['user_data'])
    return trim(get(l:user_data, s:user_data_filtertext_key, a:item['word']))
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

function! s:display_completions(timer) abort
    call complete(s:start_pos + 1, s:completion['matches'])
endfunction

function! s:handle_omnicompletion(server_name, complete_counter, data) abort
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

    if g:lsp_async_completion
        call complete(col('.'), l:matches)
    else
        let s:completion['matches'] = l:matches
        let s:completion['status'] = s:completion_status_success
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
                \ 'on_notification': function('s:handle_omnicompletion', [l:server_name, s:completion['counter']]),
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

    if g:lsp_insert_text_enabled && has_key(a:item, 'insertText') && !empty(a:item['insertText'])
        if has_key(a:item, 'insertTextFormat') && a:item['insertTextFormat'] != 1
            let l:word = a:item['label']
        else
            let l:word = a:item['insertText']
        endif
        let l:abbr = a:item['label']
    else
        let l:word = a:item['label']
        let l:abbr = a:item['label']
    endif

    let l:kind = lsp#omni#get_kind_text(a:item, l:server_name)

    let l:completion = {
                \ 'word': l:word,
                \ 'abbr': l:abbr,
                \ 'menu': '',
                \ 'info': '',
                \ 'icase': 1,
                \ 'dup': 1,
                \ 'empty': 1,
                \ 'kind': l:kind}

    " check support user_data.
    " if not support but g:lsp_text_edit_enabled enabled,
    " then print information to user and add information to log file.
    if !s:is_user_data_support && g:lsp_text_edit_enabled
        let l:no_support_error_message = 'textEdit support on omni complete requires Vim 8.0 patch 1493 or later(please check g:lsp_text_edit_enabled)'
        call lsp#utils#error(l:no_support_error_message)
        call lsp#log(l:no_support_error_message)
    endif

    let l:user_data = {}

    " Use '-1' to signal "no specific insertion point" set.
    let l:user_data[s:user_data_insert_start_key] = -1

    " add user_data in completion item, when
    "     1. provided user_data
    "     2. provided textEdit or additionalTextEdits
    "     3. textEdit value is Dictionary or additionalTextEdits is non-empty list
    if g:lsp_text_edit_enabled
        let l:text_edit = get(a:item, 'textEdit', v:null)
        let l:additional_text_edits = get(a:item, 'additionalTextEdits', v:null)

        " type check
        if type(l:text_edit) == type({})
            let l:user_data[s:user_data_key] = l:text_edit
            let l:user_data[s:user_data_insert_start_key] = l:text_edit['range']['start']['character']
        endif

        if type(l:additional_text_edits) == type([]) && !empty(l:additional_text_edits)
            let l:user_data[s:user_data_additional_edits_key] = l:additional_text_edits
        endif
    endif

    " Store filterText in user_data
    if s:is_user_data_support && has_key(a:item, 'filterText')
        let l:user_data[s:user_data_filtertext_key] = a:item['filterText']
    endif

    if !empty(l:user_data)
        let l:completion['user_data'] = json_encode(l:user_data)
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
            let l:completion['info'] .= a:item['documentation']['value']
        endif
    endif

    return l:completion
endfunction

function! lsp#omni#get_vim_completion_item(...) abort
    return call(g:lsp_get_vim_completion_item[0], a:000)
endfunction

augroup lsp_completion_item_text_edit
    autocmd!
    autocmd CompleteDone * call <SID>apply_text_edits()
augroup END

function! s:apply_text_edits() abort
    " textEdit support function(callin from CompleteDone).
    "
    " expected user_data structure:
    "     v:completed_item['user_data']: {
    "       'vim-lsp/textEdit': {
    "         'range': { ...(snip) },
    "         'newText': 'yyy'
    "       },
    "       'vim-lsp/additionalTextEdits': [
    "         {
    "           'range': { ...(snip) },
    "           'newText': 'yyy'
    "         },
    "         ...
    "       ],
    "     }
    if !g:lsp_text_edit_enabled
        doautocmd User lsp_complete_done
        return
    endif

    " completion faild or not select complete item
    if empty(v:completed_item)
        doautocmd User lsp_complete_done
        return
    endif

    " check user_data
    if !has_key(v:completed_item, 'user_data')
        doautocmd User lsp_complete_done
        return
    endif

    " check user_data type is Dictionary and user_data['vim-lsp/textEdit']
    try
        let l:user_data = json_decode(v:completed_item['user_data'])
    catch
        " do nothing if user_data is not json type string.
        doautocmd User lsp_complete_done
        return
    endtry

    if type(l:user_data) != type({})
        doautocmd User lsp_complete_done
        return
    endif

    let l:all_text_edits = []

    " expand textEdit range, for omni complet inserted text.
    let l:text_edit = get(l:user_data, s:user_data_key, {})
    if !empty(l:text_edit)
        let l:expanded_text_edit = s:expand_range(l:text_edit, strchars(v:completed_item['word']))
        call add(l:all_text_edits, l:expanded_text_edit)
    endif

    if has_key(l:user_data, s:user_data_additional_edits_key)
        let l:all_text_edits += l:user_data[s:user_data_additional_edits_key]
    endif

    " save cursor position in a mark, vim will move it appropriately when
    " applying edits
    let l:saved_mark = getpos("'a")
    " move to end of newText but in two steps (as column may not exist yet)
    let [l:pos, l:col_offset] = s:get_cursor_pos_and_edit_length(l:text_edit)
    call setpos("'a", l:pos)

    " apply textEdits
    if !empty(l:all_text_edits)
        call lsp#utils#text_edit#apply_text_edits(lsp#utils#get_buffer_uri(), l:all_text_edits)
    endif

    let l:pos = getpos("'a")
    let l:pos[2] += l:col_offset
    call setpos("'a", l:saved_mark)
    call setpos('.', l:pos)

    doautocmd User lsp_complete_done
endfunction

function! s:expand_range(text_edit, expand_length) abort
    let l:expanded_text_edit = a:text_edit
    let l:expanded_text_edit['range']['end']['character'] += a:expand_length

    return l:expanded_text_edit
endfunction

function! s:get_cursor_pos_and_edit_length(text_edit) abort
    if !empty(a:text_edit)
        let l:start = a:text_edit['range']['start']
        let l:line = l:start['line'] + 1
        let l:char = l:start['character']
        let l:col = lsp#utils#to_col('%', l:line, l:char)
        let l:length = len(a:text_edit['newText'])
        let l:pos = [0, l:line, l:col, 0]
    else
        let l:length = 0
        let l:pos = getpos('.')
    endif

    return [l:pos, l:length]
endfunction

function! lsp#omni#get_completion_item_kinds() abort
    return map(keys(s:default_completion_item_kinds), {idx, key -> str2nr(key)})
endfunction

" }}}
