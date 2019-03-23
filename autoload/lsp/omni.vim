" constants {{{

let s:kind_text_mappings = {
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

let s:completion_status_success = 'success'
let s:completion_status_failed = 'failed'
let s:completion_status_pending = 'pending'

let s:is_user_data_support = has('patch-8.0.1493')
let s:user_data_key = 'vim-lsp/textEdit'

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
            let l:base = tolower(a:base)
            let s:completion['matches'] = filter(s:completion['matches'], {_, match -> stridx(tolower(match['word']), l:base) == 0})
            let s:completion['status'] = ''
            return s:completion['matches']
        endif
    endif
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

    let l:result = s:get_completion_result(a:data)
    let l:matches = l:result['matches']

    if g:lsp_async_completion
        call complete(col('.'), l:matches)
    else
        let s:completion['matches'] = l:matches
        let s:completion['status'] = s:completion_status_success
    endif
endfunction

function! lsp#omni#get_kind_text(completion_item) abort
    return has_key(a:completion_item, 'kind') && has_key(s:kind_text_mappings, a:completion_item['kind']) ? s:kind_text_mappings[a:completion_item['kind']] : ''
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

function! s:get_completion_result(data) abort
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

    let l:matches = type(l:items) == type([]) ? map(l:items, {_, item -> lsp#omni#get_vim_completion_item(item, 1) }) : []

    return {'matches': l:matches, 'incomplete': l:incomplete}
endfunction


function! s:remove_typed_part(word) abort
    let l:current_line = strpart(getline('.'), 0, col('.') - 1)

    let l:overlap_length = 0
    let l:i = 1
    let l:max_possible_overlap = min([len(a:word), len(l:current_line)])

    while l:i <= l:max_possible_overlap
        let l:current_line_suffix = strpart(l:current_line, len(l:current_line) - l:i, l:i)
        let l:word_prefix = strpart(a:word, 0, l:i)

        if l:current_line_suffix == l:word_prefix
            let l:overlap_length = l:i
        endif

        let l:i += 1
    endwhile

    return strpart(a:word, l:overlap_length)
endfunction

function! lsp#omni#get_vim_completion_item(item, ...) abort
    let l:do_remove_typed_part = get(a:, 1, 0)

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

    if l:do_remove_typed_part
        let l:word = s:remove_typed_part(l:word)
    endif
    let l:kind = lsp#omni#get_kind_text(a:item)

    let l:completion = {
                \ 'word': l:word,
                \ 'abbr': l:abbr,
                \ 'menu': '',
                \ 'info': '',
                \ 'icase': 1,
                \ 'dup': 1,
                \ 'kind': l:kind}

    " check support user_data.
    " if not support but g:lsp_text_edit_enabled enabled,
    " then print information to user and add information to log file.
    if !s:is_user_data_support && g:lsp_text_edit_enabled
        let l:no_support_error_message = 'textEdit support on omni complete requires Vim 8.0 patch 1493 or later(please check g:lsp_text_edit_enabled)'
        call lsp#utils#error(l:no_support_error_message)
        call lsp#log(l:no_support_error_message)
    endif

    " add user_data in completion item, if supported user_data.
    if g:lsp_text_edit_enabled && has_key(a:item, 'textEdit')
        let l:text_edit = a:item['textEdit']
        let l:user_data = {
                \ s:user_data_key : l:text_edit
                \ }

        let l:completion['user_data'] = json_encode(l:user_data)
    endif

    if has_key(a:item, 'detail') && !empty(a:item['detail'])
        let l:completion['menu'] = a:item['detail']
    endif

    if has_key(a:item, 'documentation')
        if type(a:item['documentation']) == type('')
            let l:completion['info'] .= a:item['documentation']
        endif
    endif

    return l:completion
endfunction

augroup lsp_completion_item_text_edit
    autocmd!
    autocmd CompleteDone * call <SID>apply_text_edit()
augroup END

function! s:apply_text_edit() abort
    " textEdit support function(callin from CompleteDone).
    "
    " expected user_data structure:
    "     v:completed_item['user_data']: {
    "       'vim-lsp/textEdit': {
    "         'range': { ...(snip) },
    "         'newText': 'yyy'
    "        },
    "     }
    if !g:lsp_text_edit_enabled
        return
    endif

    " completion faild or not select complete item
    if empty(v:completed_item) || v:completed_item['word'] ==# ''
        return
    endif

    " check user_data
    if !has_key(v:completed_item, 'user_data')
        return
    endif

    " check user_data type is Dictionary and user_data['vim-lsp/textEdit']
    let l:user_data = json_decode(v:completed_item['user_data'])
    if !(type(l:user_data) == type({}) && has_key(l:user_data, s:user_data_key))
        return
    endif

    " expand textEdit range, for omni complet inserted text.
    let l:text_edit = l:user_data[s:user_data_key]
    let l:expanded_text_edit = s:expand_range(l:text_edit, len(v:completed_item['word']))

    " apply textEdit
    call lsp#utils#text_edit#apply_text_edits(expand('%:p'), [l:expanded_text_edit])

    " move to end of newText
    " TODO: add user definition cursor position mechanism
    let l:start = l:text_edit['range']['start']
    let l:line = l:start['line'] + 1
    let l:col = l:start['character']
    let l:new_text_length = len(l:text_edit['newText']) + 1
    call cursor(l:line, l:col + l:new_text_length)
endfunction

function! s:expand_range(text_edit, expand_length) abort
    let expanded_text_edit = a:text_edit
    let l:expanded_text_edit['range']['end']['character'] += a:expand_length

    return l:expanded_text_edit
endfunction

" }}}
