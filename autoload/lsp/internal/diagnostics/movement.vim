function! s:severity_of(diagnostic) abort
    return get(a:diagnostic, 'severity', 1)
endfunction

function! lsp#internal#diagnostics#movement#_next_error(...) abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 1 })
    let l:options = lsp#utils#parse_command_options(a:000)
    call s:next_diagnostic(l:diagnostics, l:options)
endfunction

function! lsp#internal#diagnostics#movement#_next_warning(...) abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 2 })
    let l:options = lsp#utils#parse_command_options(a:000)
    call s:next_diagnostic(l:diagnostics, l:options)
endfunction

function! lsp#internal#diagnostics#movement#_next_diagnostics(...) abort
    let l:options = lsp#utils#parse_command_options(a:000)
    call s:next_diagnostic(s:get_all_buffer_diagnostics(), l:options)
endfunction

function! s:next_diagnostic(diagnostics, options) abort
    if !len(a:diagnostics)
        return
    endif
    call sort(a:diagnostics, 's:compare_diagnostics')

    let l:wrap = 1
    if has_key(a:options, 'wrap')
        let l:wrap = a:options['wrap']
    endif

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
        if !l:wrap
            return
        endif
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

function! lsp#internal#diagnostics#movement#_previous_error(...) abort
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 1 })
    let l:options = lsp#utils#parse_command_options(a:000)
    call s:previous_diagnostic(l:diagnostics, l:options)
endfunction

function! lsp#internal#diagnostics#movement#_previous_warning(...) abort
    let l:options = lsp#utils#parse_command_options(a:000)
    let l:diagnostics = filter(s:get_all_buffer_diagnostics(),
        \ {_, diagnostic -> s:severity_of(diagnostic) ==# 2 })
    call s:previous_diagnostic(l:diagnostics, l:options)
endfunction

function! lsp#internal#diagnostics#movement#_previous_diagnostics(...) abort
    let l:options = lsp#utils#parse_command_options(a:000)
    call s:previous_diagnostic(s:get_all_buffer_diagnostics(), l:options)
endfunction

function! s:previous_diagnostic(diagnostics, options) abort
    if !len(a:diagnostics)
        return
    endif
    call sort(a:diagnostics, 's:compare_diagnostics')

    let l:wrap = 1
    if has_key(a:options, 'wrap')
        let l:wrap = a:options['wrap']
    endif

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
        if !l:wrap
            return
        endif
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
    let l:server = get(a:000, 0, '')

    let l:bufnr = bufnr('%')
    let l:uri = lsp#utils#get_buffer_uri(l:bufnr)

    if !lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr)
        return []
    endif

    let l:diagnostics_by_server = lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri)
    let l:diagnostics = []
    if empty(l:server)
        for l:item in values(l:diagnostics_by_server)
            let l:diagnostics += lsp#utils#iteratable(l:item['params']['diagnostics'])
        endfor
    else
        if has_key(l:diagnostics_by_server, l:server)
            let l:diagnostics = lsp#utils#iteratable(l:diagnostics_by_server[l:server]['params']['diagnostics'])
        endif
    endif

    return l:diagnostics
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
" vim sw=4 ts=4 et
