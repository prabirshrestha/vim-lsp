let s:last_req_id = 0
let s:list = []

function! lsp#ui#vim#get_document_symbols() abort
    let l:servers = lsp#get_whitelisted_servers()
    let s:list = []
    let s:last_req_id = s:last_req_id + 1

    if len(l:servers) == 0
        echom 'Retrieving symbols not supported for ' . &filetype
    endif

    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/documentSymbol',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \ },
            \ 'on_notification': function('s:handle_document_symbol', [l:server, s:last_req_id]),
            \ })
    endfor

    echom 'Retrieving document symbols ...'
endfunction

function! s:handle_document_symbol(server, last_req_id, data) abort
    if a:last_req_id != s:last_req_id
        return
    endif

    if lsp#client#is_error(a:data)
        echom 'Failed to retrieve document symbols for ' . a:server
    endif

    echom 'Retrieved document symbols'

    let l:list = lsp#ui#vim#utils#to_loc_list(a:data)
    let s:list += l:list

    call lsp#log('---------document_symbol', s:list)

    call setqflist(s:list)

    if empty(s:list)
        echom 'No document symbols found'
    else
        copen
    endif
endfunction

