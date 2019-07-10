let s:is_win = has('win32') || has('win64')
let s:diagnostics = {} " { uri: { 'server_name': response } }

function! lsp#ui#vim#diagnostics#handle_text_document_publish_diagnostics(server_name, data) abort
    if lsp#client#is_error(a:data['response'])
        return
    endif
    let l:uri = a:data['response']['params']['uri']
    if s:is_win
        let l:uri = substitute(l:uri, '^file:///[a-zA-Z]\zs%3[aA]', ':', '')
    endif
    if !has_key(s:diagnostics, l:uri)
        let s:diagnostics[l:uri] = {}
    endif
    let s:diagnostics[l:uri][a:server_name] = a:data

    call lsp#ui#vim#virtual#set(a:server_name, a:data)
    call lsp#ui#vim#highlights#set(a:server_name, a:data)
    call lsp#ui#vim#diagnostics#textprop#set(a:server_name, a:data)
    call lsp#ui#vim#signs#set(a:server_name, a:data)
endfunction

function! lsp#ui#vim#diagnostics#document_diagnostics() abort
    if !g:lsp_diagnostics_enabled
        call lsp#utils#error('Diagnostics manually disabled -- g:lsp_diagnostics_enabled = 0')
        return
    endif

    let l:uri = lsp#utils#get_buffer_uri()

    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    if !l:has_diagnostics
        call lsp#utils#error('No diagnostics results')
        return
    endif

    let l:result = []
    for [l:server_name, l:data] in items(l:diagnostics)
        let l:result += lsp#ui#vim#utils#diagnostics_to_loc_list(l:data)
    endfor

    call setqflist(l:result)

    " autocmd FileType qf setlocal wrap

    if empty(l:result)
        call lsp#utils#error('No diagnostics results found')
    else
        echo 'Retrieved diagnostics results'
        botright copen
    endif
endfunction

function! lsp#ui#vim#diagnostics#get_diagnostics_under_cursor() abort
    let l:diagnostics = s:get_all_buffer_diagnostics()
    if !len(l:diagnostics)
        return
    endif

    let l:line = line('.')
    let l:col = col('.')

    let l:closest_diagnostics = {}
    let l:closest_distance = -1

    for l:diagnostic in l:diagnostics
        let l:range = l:diagnostic['range']
        let l:start_line = l:range['start']['line'] + 1
        let l:start_col = l:range['start']['character'] + 1
        let l:end_line = l:range['end']['line'] + 1
        let l:end_character = l:range['end']['character'] + 1

        if l:line == l:start_line
            let l:distance = abs(l:start_col - l:col)
            if l:closest_distance < 0 || l:distance < l:closest_distance
                let l:closest_diagnostics = l:diagnostic
                let l:closest_distance = l:distance
            endif
        endif
    endfor

    return l:closest_diagnostics
endfunction

function! lsp#ui#vim#diagnostics#next_error() abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> diagnostic['severity'] ==# 1 })
    if !len(l:diagnostics)
        return
    endif
    call sort(l:diagnostics, 's:compare_diagnostics')

    let l:view = winsaveview()
    let l:next_line = 0
    let l:next_col = 0
    for l:diagnostic in l:diagnostics
        let l:line = l:diagnostic['range']['start']['line'] + 1
        let l:col = l:diagnostic['range']['start']['character'] + 1
        if l:line > l:view['lnum']
            \ || (l:line == l:view['lnum'] && l:col > l:view['col'] + 1)
            let l:next_line = l:line
            let l:next_col = l:col - 1
            break
        endif
    endfor

    if l:next_line == 0
        " Wrap to start
        let l:next_line = l:diagnostics[0]['range']['start']['line'] + 1
        let l:next_col = l:diagnostics[0]['range']['start']['character']
    endif

    let l:view['lnum'] = l:next_line
    let l:view['col'] = l:next_col
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let totalnum = line('$')
    if totalnum > l:height
        let l:half = l:height / 2
        if l:totalnum - l:half < l:view['lnum']
            let l:view['topline'] = l:totalnum - l:height + 1
        else
            let l:view['topline'] = l:view['lnum'] - l:half
        endif
    endif
    call winrestview(l:view)
endfunction

function! lsp#ui#vim#diagnostics#previous_error() abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> diagnostic['severity'] ==# 1 })
    if !len(l:diagnostics)
        return
    endif
    call sort(l:diagnostics, 's:compare_diagnostics')

    let l:view = winsaveview()
    let l:next_line = 0
    let l:next_col = 0
    let l:index = len(l:diagnostics) - 1
    while l:index >= 0
        let l:line = l:diagnostics[l:index]['range']['start']['line'] + 1
        let l:col = l:diagnostics[l:index]['range']['start']['character'] + 1
        if l:line < l:view['lnum']
            \ || (l:line == l:view['lnum'] && l:col < l:view['col'])
            let l:next_line = l:line
            let l:next_col = l:col - 1
            break
        endif
        let l:index = l:index - 1
    endwhile

    if l:next_line == 0
        " Wrap to end
        let l:next_line = l:diagnostics[-1]['range']['start']['line'] + 1
        let l:next_col = l:diagnostics[-1]['range']['start']['character']
    endif

    let l:view['lnum'] = l:next_line
    let l:view['col'] = l:next_col
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let totalnum = line('$')
    if totalnum > l:height
        let l:half = l:height / 2
        if l:totalnum - l:half < l:view['lnum']
            let l:view['topline'] = l:totalnum - l:height + 1
        else
            let l:view['topline'] = l:view['lnum'] - l:half
        endif
    endif
    call winrestview(l:view)
endfunction

function! s:get_diagnostics(uri) abort
    if has_key(s:diagnostics, a:uri)
        return [1, s:diagnostics[a:uri]]
    else
        if s:is_win
            " vim in windows always uses upper case for drive letter, so use lowercase in case lang server uses lowercase
            " https://github.com/theia-ide/typescript-language-server/issues/23
            let l:uri = substitute(a:uri, '^' . a:uri[:8], tolower(a:uri[:8]), '')
            if has_key(s:diagnostics, l:uri)
                return [1, s:diagnostics[l:uri]]
            endif
        endif
    endif
    return [0, {}]
endfunction

" Get diagnostics for the current buffer URI from all servers
function! s:get_all_buffer_diagnostics() abort
    let l:uri = lsp#utils#get_buffer_uri()

    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    if !l:has_diagnostics
        return []
    endif

    let l:all_diagnostics = []
    for [l:server_name, l:data] in items(l:diagnostics)
        call extend(l:all_diagnostics, l:data['response']['params']['diagnostics'])
    endfor

    return l:all_diagnostics
endfunction

function! s:compare_diagnostics(d1, d2) abort
    let l:range1 = a:d1['range']
    let l:line1 = l:range1['start']['line'] + 1
    let l:col1 = l:range1['start']['character'] + 1
    let l:range2 = a:d2['range']
    let l:line2 = l:range2['start']['line'] + 1
    let l:col2 = l:range2['start']['character'] + 1

    if l:line1 == l:line2
        return l:col1 == l:col2 ? 0 : l:col1 > l:col2 ? 1 : -1
    else
        return l:line1 > l:line2 ? 1 : -1
    endif
endfunction

let s:diagnostic_kinds = {
    \ 1: 'error',
    \ 2: 'warning',
    \ 3: 'information',
    \ 4: 'hint',
    \ }

function! lsp#ui#vim#diagnostics#get_buffer_diagnostics_counts() abort
    let l:counts = {
        \ 'error': 0,
        \ 'warning': 0,
        \ 'information': 0,
        \ 'hint': 0,
        \ }
    let l:uri = lsp#utils#get_buffer_uri()
    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    for [l:server_name, l:data] in items(l:diagnostics)
        for l:diag in l:data['response']['params']['diagnostics']
            let l:key = get(s:diagnostic_kinds, l:diag['severity'], 'error')
            let l:counts[l:key] += 1
        endfor
    endfor
    return l:counts
endfunction

function! lsp#ui#vim#diagnostics#get_buffer_first_error_line() abort
    let l:uri = lsp#utils#get_buffer_uri()
    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    let l:first_error_line = v:null
    for [l:server_name, l:data] in items(l:diagnostics)
        for l:diag in l:data['response']['params']['diagnostics']
            if l:diag['severity'] ==# 1 && (l:first_error_line ==# v:null || l:first_error_line ># l:diag['range']['start']['line'])
                let l:first_error_line = l:diag['range']['start']['line']
            endif
        endfor
    endfor
    return l:first_error_line ==# v:null ? v:null : l:first_error_line + 1
endfunction
" vim sw=4 ts=4 et
