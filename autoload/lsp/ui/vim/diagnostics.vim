let s:is_win = has('win32') || has('win64')
let s:diagnostics = {} " { uri: { 'server_name': response } }

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

    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    if !l:has_diagnostics
        call lsp#utils#error('No diagnostics results')
        return
    endif

    let l:result = []
    for [l:server_name, l:data] in items(l:diagnostics)
        let l:result += lsp#ui#vim#utils#diagnostics_to_loc_list(l:data)
    endfor

    call setqflist(l:result)

    " autocmd FileType qf setlocal wrap

    if empty(l:result)
        call lsp#utils#error('No diagnostics results found')
    else
        echo 'Retrieved diagnostics results'
        botright copen
    endif
endfunction

function! lsp#ui#vim#diagnostics#get_diagnostics_under_cursor() abort
    let l:uri = lsp#utils#get_buffer_uri()

    let [l:has_diagnostics, l:diagnostics] = s:get_diagnostics(l:uri)
    if !l:has_diagnostics
        return
    endif

    let l:line = line('.')
    let l:col = col('.')

    let l:closeset_diagnostics = {}
    let l:closeset_distance = -1

    for [l:server_name, l:data] in items(l:diagnostics)
        for l:diagnostic in l:data['response']['params']['diagnostics']
            let l:range = l:diagnostic['range']
            let l:start_line = l:range['start']['line'] + 1
            let l:start_col = l:range['start']['character'] + 1
            let l:end_line = l:range['end']['line'] + 1
            let l:end_character = l:range['end']['character'] + 1

            if l:line == l:start_line
                let l:distance = abs(l:start_col - l:col)
                if l:closeset_distance < 0 || l:distance < l:closeset_distance
                    let l:closeset_diagnostics = l:diagnostic
                    let l:closeset_distance = l:distance
                endif
            endif
        endfor
    endfor

    return l:closeset_diagnostics
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
    return [0, []]
endfunction
