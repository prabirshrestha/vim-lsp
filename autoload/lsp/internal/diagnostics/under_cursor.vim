" Returns a diagnostic object, or empty dictionary if no diagnostics are
" available.
" options = {
"   'server': '',        " optional
" }
function! lsp#internal#diagnostics#under_cursor#get_diagnostic(...) abort
    let l:options = get(a:000, 0, {})
    let l:server = get(l:options, 'server', '')
    let l:bufnr = bufnr('%')

    if !lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr)
        return {}
    endif

    let l:uri = lsp#utils#get_buffer_uri(l:bufnr)

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
