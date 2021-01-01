" options = {
"   buffers: '1'    " optional string, defaults to current buffer, '*' for all buffers
" }
function! lsp#internal#diagnostics#document_diagnostics_command#do(options) abort
    if !g:lsp_diagnostics_enabled
        call lsp#utils#error(':LspDocumentDiagnostics g:lsp_diagnostics_enabled must be enabled')
        return
    endif

    let l:buffers = get(a:options, 'buffers', '')

    let l:filtered_diagnostics = {}

    if l:buffers ==# '*'
        let l:filtered_diagnostics = lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_uri_and_server()
    else
        let l:uri = lsp#utils#get_buffer_uri()
        if !empty(l:uri)
            let l:filtered_diagnostics[l:uri] = lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri)
        endif
    endif

    let l:result = []
    for [l:uri, l:value] in items(l:filtered_diagnostics)
        if lsp#internal#diagnostics#state#_is_enabled_for_buffer(bufnr(lsp#utils#uri_to_path(l:uri)))
            for l:diagnostics in values(l:value)
                let l:result += lsp#ui#vim#utils#diagnostics_to_loc_list({ 'response': l:diagnostics })
            endfor
        endif
    endfor

    if empty(l:result)
        call lsp#utils#error('No diagnostics results')
        return
    else
        call setloclist(0, l:result)
        echo 'Retrieved diagnostics results'
        botright lopen
    endif
endfunction
