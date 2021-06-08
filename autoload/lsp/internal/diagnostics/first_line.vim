" Return first error line or v:null if there are no errors
" available.
" options = {
"   'bufnr': '',        " optional
" }
function! lsp#internal#diagnostics#first_line#get_first_error_line(options) abort
    let l:bufnr = get(a:options, 'bufnr', bufnr('%'))

    if !lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr)
        return v:null
    endif

    let l:uri = lsp#utils#get_buffer_uri(l:bufnr)
    let l:diagnostics_by_server = lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri)

    let l:first_error_line = v:null
    for l:diagnostics_response in values(l:diagnostics_by_server)
        for l:item in lsp#utils#iteratable(l:diagnostics_response['params']['diagnostics'])
            let l:severity = get(l:item, 'severity', 1)
            if l:severity ==# 1 && (l:first_error_line ==# v:null || l:first_error_line ># l:item['range']['start']['line'])
                let l:first_error_line = l:item['range']['start']['line']
            endif
        endfor
    endfor
    return l:first_error_line ==# v:null ? v:null : l:first_error_line + 1
endfunction
