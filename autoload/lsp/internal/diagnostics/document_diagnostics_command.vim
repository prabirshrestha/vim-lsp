" options = {
"   buffers: '' . bufnr('%')     " optional, '*' for all buffers
" }
function! lsp#internal#diagnostics#document_diagnostics_command#do(options) abort
    if !g:lsp_diagnostics_enabled
        call lsp#utils#error(':LspDocumentDiagnostics', 'g:lsp_diagnostics_enabled must be enabled')
        return
    endif

    let l:buffers = get(a:options, 'buffers', bufnr('%'))
    if type(l:buffers) == type('')
        let l:buffers = split(l:buffers, ',')
    endif

    for l:buffer in l:buffers
    endfor

    echom json_encode(l:buffers)
endfunction

" :LspDocumentDiagnostics --ui=quickfix --buffers=*
