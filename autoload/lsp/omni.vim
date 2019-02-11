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
    let a:do_remove_typed_part = get(a:, 1, 0)

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

    if g:lsp_ultisnips_integration && has_key(a:item, 'insertTextFormat') && a:item['insertTextFormat'] == 2
        let l:snippet = substitute(a:item['insertText'], '\%x00', '\\n', 'g')
        let l:word = trim(a:item['label'])
        let l:trigger = l:word
    endif

    if a:do_remove_typed_part
        let l:word = s:remove_typed_part(l:word)
    endif
    let l:menu = lsp#omni#get_kind_text(a:item)
    let l:completion = { 'word': l:word, 'abbr': l:abbr, 'menu': l:menu, 'info': '', 'icase': 1, 'dup': 1 }

    if has_key(a:item, 'detail') && !empty(a:item['detail'])
        if empty(l:menu)
            let l:completion['menu'] = a:item['detail']
        else
            let l:completion['menu'] = '[' . l:menu . '] ' . a:item['detail']
        endif
        let l:completion['info'] .= a:item['detail'] . ' '
    endif

    if has_key(a:item, 'documentation')
        if type(a:item['documentation']) == type('')
            let l:completion['info'] .= a:item['documentation']
        endif
    endif

    if exists('l:snippet')
        let l:completion['user_data'] = string([l:trigger, l:snippet])
    endif

    return l:completion
endfunction

function! s:expand_snippet(timer)
    call feedkeys("\<C-r>=UltiSnips#Anon(\"" . s:snippet . "\", \"" . s:trigger . "\", '', 'i')\<CR>")
endfunction

function! s:handle_snippet(item)
    if !has_key(a:item, 'user_data')
        return
    endif

    execute 'let l:user_data = ' . a:item['user_data']

    let s:trigger = l:user_data[0]
    let s:snippet = l:user_data[1]

    call timer_start(0, function('s:expand_snippet'))
endfunction

if g:lsp_ultisnips_integration
    augroup lsp_ultisnips
        autocmd!
        autocmd CompleteDone * call s:handle_snippet(v:completed_item)
    augroup end
endif

" }}}
