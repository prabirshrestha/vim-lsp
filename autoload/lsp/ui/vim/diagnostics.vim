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

function! lsp#ui#vim#diagnostics#force_refresh(bufnr) abort
    let l:data = lsp#ui#vim#diagnostics#get_document_diagnostics(a:bufnr)
    if !empty(l:data)
        for [l:server_name, l:response] in items(l:data)
            call lsp#ui#vim#virtual#set(l:server_name, l:response)
            call lsp#ui#vim#highlights#set(l:server_name, l:response)
            call lsp#ui#vim#diagnostics#textprop#set(l:server_name, l:response)
            call lsp#ui#vim#signs#set(l:server_name, l:response)
        endfor
    endif
endfunction

function! lsp#ui#vim#diagnostics#get_document_diagnostics(bufnr) abort
    return get(s:diagnostics, lsp#utils#get_buffer_uri(a:bufnr), {})
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
    for l:data in values(l:diagnostics)
        let l:result += lsp#ui#vim#utils#diagnostics_to_loc_list(l:data)
    endfor

    call setloclist(0, l:result)

    " autocmd FileType qf setlocal wrap

    if empty(l:result)
        call lsp#utils#error('No diagnostics results found')
    else
        echo 'Retrieved diagnostics results'
        botright lopen
    endif
endfunction

" Returns a diagnostic object, or empty dictionary if no diagnostics are available.
"
" Note: Consider renaming this method (s/diagnostics/diagnostic) to make
" it clear that it returns just one diagnostic, not a list.
function! lsp#ui#vim#diagnostics#get_diagnostics_under_cursor(...) abort
    let l:target_server_name = get(a:000, 0, '')

    let l:diagnostics = s:get_all_buffer_diagnostics(l:target_server_name)
    if !len(l:diagnostics)
        return
    endif

    let l:line = line('.')
    let l:col = col('.')

    let l:closest_diagnostic = {}
    let l:closest_distance = -1

    for l:diagnostic in l:diagnostics
        let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim('%', l:diagnostic['range']['start'])

        if l:line == l:start_line
            let l:distance = abs(l:start_col - l:col)
            if l:closest_distance < 0 || l:distance < l:closest_distance
                let l:closest_diagnostic = l:diagnostic
                let l:closest_distance = l:distance
            endif
        endif
    endfor

    return l:closest_diagnostic
endfunction

function! s:severity_of(diagnostic) abort
    return get(a:diagnostic, 'severity', 1)
endfunction

function! lsp#ui#vim#diagnostics#next_error() abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 1 })
    call s:next_diagnostic(l:diagnostics)
endfunction

function! lsp#ui#vim#diagnostics#next_warning() abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 2 })
    call s:next_diagnostic(l:diagnostics)
endfunction

function! lsp#ui#vim#diagnostics#next_diagnostic() abort
    call s:next_diagnostic(s:get_all_buffer_diagnostics())
endfunction

function! s:next_diagnostic(diagnostics) abort
    if !len(a:diagnostics)
        return
    endif
    call sort(a:diagnostics, 's:compare_diagnostics')

    let l:view = winsaveview()
    let l:next_line = 0
    let l:next_col = 0
    for l:diagnostic in a:diagnostics
        let [l:line, l:col] = lsp#utils#position#lsp_to_vim('%', l:diagnostic['range']['start'])
        if l:line > l:view['lnum']
            \ || (l:line == l:view['lnum'] && l:col > l:view['col'] + 1)
            let l:next_line = l:line
            let l:next_col = l:col - 1
            break
        endif
    endfor

    if l:next_line == 0
        " Wrap to start
        let [l:next_line, l:next_col] = lsp#utils#position#lsp_to_vim('%', a:diagnostics[0]['range']['start'])
        let l:next_col -= 1
    endif

    let l:view['lnum'] = l:next_line
    let l:view['col'] = l:next_col
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let l:totalnum = line('$')
    if l:totalnum > l:height
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
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 1 })
    call s:previous_diagnostic(l:diagnostics)
endfunction

function! lsp#ui#vim#diagnostics#previous_warning() abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 2 })
    call s:previous_diagnostic(l:diagnostics)
endfunction

function! lsp#ui#vim#diagnostics#previous_diagnostic() abort
    call s:previous_diagnostic(s:get_all_buffer_diagnostics())
endfunction

function! s:previous_diagnostic(diagnostics) abort
    if !len(a:diagnostics)
        return
    endif
    call sort(a:diagnostics, 's:compare_diagnostics')

    let l:view = winsaveview()
    let l:next_line = 0
    let l:next_col = 0
    let l:index = len(a:diagnostics) - 1
    while l:index >= 0
        let [l:line, l:col] = lsp#utils#position#lsp_to_vim('%', a:diagnostics[l:index]['range']['start'])
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
        let [l:next_line, l:next_col] = lsp#utils#position#lsp_to_vim('%', a:diagnostics[-1]['range']['start'])
        let l:next_col -= 1
    endif

    let l:view['lnum'] = l:next_line
    let l:view['col'] = l:next_col
    let l:view['topline'] = 1
    let l:height = winheight(0)
    let l:totalnum = line('$')
    if l:totalnum > l:height
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
function! s:get_all_buffer_diagnostics(...) abort
    let l:target_server_name = get(a:000, 0, '')

    let l:uri = lsp#utils#get_buffer_uri()

    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    if !l:has_diagnostics
        return []
    endif

    let l:all_diagnostics = []
    for [l:server_name, l:data] in items(l:diagnostics)
        if empty(l:target_server_name) || l:server_name ==# l:target_server_name
            call extend(l:all_diagnostics, l:data['response']['params']['diagnostics'])
        endif
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
            let l:key = get(s:diagnostic_kinds, s:severity_of(l:diag), 'error')
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
            if s:severity_of(l:diag) ==# 1 && (l:first_error_line ==# v:null || l:first_error_line ># l:diag['range']['start']['line'])
                let l:first_error_line = l:diag['range']['start']['line']
            endif
        endfor
    endfor
    return l:first_error_line ==# v:null ? v:null : l:first_error_line + 1
endfunction
" vim sw=4 ts=4 et
