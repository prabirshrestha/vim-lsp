function! lsp#ui#fzf#get_document_symbols() abort
    let l:servers = lsp#get_whitelisted_servers()
    let l:tempfile = tempname()
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/documentSymbol',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \ },
            \ 'on_notification': function('s:handle_document_symbol', [l:tempfile, l:server]),
            \ })
    endfor
    call writefile([], l:tempfile)
    call lsp#log(l:tempfile, 'before')
    call fzf#run({ 'source': 'tail -f ' . l:tempfile, 'sink': 'e', 'down': '40%' })
    call lsp#log('running')
    call writefile(['a'], l:tempfile, 'a')
endfunction

function! s:handle_document_symbol(file, server, data) abort
    " call fzf#run({ 'source': ['a', 'b'], 'sink': 'e' })
    call lsp#log(a:file, 'response')
    if lsp#client#is_error(a:data['response'])
        call writefile(['error'], a:file, 'a')
    else
        call writefile(['hello.ts', 'world.ts'], a:file, 'a')
    endif
endfunction

