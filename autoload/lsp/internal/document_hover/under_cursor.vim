" https://microsoft.github.io/language-server-protocol/specification#textDocument_hover
" options - {
"   server - 'server_name'		" optional
" }
function! lsp#internal#document_hover#under_cursor#do(options) abort
    let l:bufnr = bufnr('%')
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_hover_provider(v:val)')
    endif

    if len(l:servers) == 0
        let l:filetype = getbufvar(l:bufnr, '&filetype')
        call lsp#utils#error('textDocument/hover not supported for ' . l:filetype)
        return
    endif

    redraw | echo 'Retrieving hover ...'

    call lsp#_new_command()

    " TODO: ask user to select server for formatting if there are multiple servers
    let l:request = {
        \ 'method': 'textDocument/hover',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \ },
        \ }
    call lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#request(server, l:request)
        \ }),
        \ lsp#callbag#tap({x->s:show_hover(x['server_name'], x['request'], x['response'])}),
        \ lsp#callbag#takeUntil(lsp#callbag#pipe(
        \   lsp#stream(),
        \   lsp#callbag#filter({x->has_key(x, 'command')}),
        \ )),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! s:show_hover(server_name, request, response) abort
    if !has_key(a:response, 'result') || empty(a:response['result']) || 
        \ empty(a:response['result']['contents'])
        call lsp#utils#error('No hover information found in server - ' . a:server_name)
        return
    endif

    call lsp#ui#vim#output#preview(a:server_name, a:response['result']['contents'], {'statusline': ' LSP Hover'})
endfunction
