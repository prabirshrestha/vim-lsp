let s:diagnostics = {} " { uri: { 'server_name': response } }

function! s:error_msg(msg) abort
    echohl ErrorMsg
    echom a:msg
    echohl NONE
endfunction

function! lsp#ui#vim#diagnostics#handle_text_document_publish_diagnostics(server_name, data) abort
    if lsp#client#is_error(a:data['response'])
        return
    endif
    let l:uri = a:data['response']['params']['uri']
    if !has_key(s:diagnostics, l:uri)
        let s:diagnostics[l:uri] = {}
    endif
    let s:diagnostics[l:uri][a:server_name] = a:data

    call lsp#ui#vim#signs#set(a:server_name, a:data)
endfunction

function! lsp#ui#vim#diagnostics#document_diagnostics() abort
    let l:uri = lsp#utils#get_buffer_uri()
    if !has_key(s:diagnostics, l:uri)
        call s:error_msg('No diagnostics results')
        return
    endif

    let l:diagnostics = s:diagnostics[l:uri]
    let l:result = []
    for [l:server_name, l:data] in items(l:diagnostics)
        let l:result += lsp#ui#vim#utils#diagnostics_to_loc_list(l:data)
    endfor

    call setqflist(l:result)

    " autocmd FileType qf setlocal wrap

    if empty(l:result)
        call s:error_msg('No diagnostics results found')
    else
        echom 'Retrieved diagnostics results'
        botright copen
    endif
endfunction
