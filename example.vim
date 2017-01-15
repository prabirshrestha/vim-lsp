" npm i -g javascript-typescript-langserver
" go get -u github.com/sourcegraph/go-langserver/langserver/cmd/langserver-go

" langserver configuration {{{
function! s:get_lsp_server_cmd_for_typescript()
    if has('win32') || has('win64')
        return ['cmd', '/c', 'javascript-typescript-stdio']
    else
        return ['sh', '-c', 'javascript-typescript-stdio']
    endif
endfunction

function! s:get_root_uri_for_typescript()
    let l:tsconfig_json_path = s:find_nearest_file(bufnr('%'), 'tsconfig.json')
    if (!empty(l:tsconfig_json_path))
        return s:path_to_uri(fnamemodify(l:tsconfig_json_path, ':p:h'))
    else
        return ''
    endif
endfunction

function! s:get_root_uri_for_go()
    " return s:path_to_uri(expand('%:p:h'))
    return s:path_to_uri(expand('~/go/src/github.com/sourcegraph/go-langserver/langserver'))
endfunction

function! s:get_lsp_server_cmd_for_go()
    return ['langserver-go', '-trace', '-logfile', expand('~/Desktop/langserver-go.log')]
endfunction
" }}}

let s:lsp_id = 0
let s:lsp_init_capabilities = {}
let s:lsp_last_request_id = 0

" Given a buffer and a filename, find the nearest file by searching upwards
" through the paths relative to the given buffer
" https://github.com/w0rp/ale/blob/master/autoload/ale/util.vim
function! s:find_nearest_file(buffer, filename) abort
    let l:buffer_filename = fnamemodify(bufname(a:buffer), ':p')

    let l:relative_path = findfile(a:filename, l:buffer_filename . ';')

    if !empty(l:relative_path)
        return fnamemodify(l:relative_path, ':p')
    endif

    return ''
endfunction

function! s:is_file_uri(uri) abort
    return  stridx(a:uri, 'file:///') == 0
endfunction

function! s:path_to_uri(path) abort
    if has('win32') || has('win64')
        return 'file:///' . s:escape_path(a:path)
    else
        return 'file://' . a:path
    endif
endfunction

function! s:uri_to_path(uri) abort
    if has('win32') || has('win64')
        return substitute(a:uri[len('file:///'):], '/', '\\', 'g')
    else
        return a:uri[len('file://'):]
    endif
endfunction

function! s:escape_path(path) abort
    return substitute(a:path, '\', '/', 'g')
endfunction

function! s:get_line_from_buf_or_file(loc_bufnr, loc_filename, loc_line) abort
    " https://github.com/tjdevries/nvim-langserver-shim/blob/cf7cf980a2d23b79eb74d6c78495587fe9703d6a/autoload/langserver/util.vim#L254-L262
    if bufnr('%') == a:loc_bufnr
        return getline(a:loc_line)
    else
        return readfile(a:loc_filename, '', a:loc_line)[a:loc_line - 1]
    endif
endfunction

function! s:get_text_document_identifier(...) abort
    let l:path = a:0
    if empty(l:path)
        let l:path = expand('%:p')
    endif
    return { 'uri': s:path_to_uri(l:path) }
endfunction

function! s:get_text_document(...) abort
    return extend(call('s:get_text_document_identifier', a:000), {
        \ 'languageId': 'typescript',
        \ 'text': join(getline(1, '$'), "\n"),
        \ 'version': 1
        \ })
endfunction

function! s:get_text_document_position_params(...) abort
  return {
        \ 'textDocument': call('s:get_text_document_identifier', a:000),
        \ 'position': s:get_position(),
        \ }
endfunction

function! s:get_reference_params(...) abort
  return extend(call('s:get_text_document_position_params', a:000), {
    \ 'context': { 'includeDeclaration': v:true }
    \ })
endfunction

function! s:get_position() abort
    return { 'line': line('.') - 1, 'character': col('.') -1 }
endfunction

let s:symbol_kinds = {
    \ '1': 'file',
    \ '2': 'module',
    \ '3': 'namespace',
    \ '4': 'package',
    \ '5': 'class',
    \ '6': 'method',
    \ '7': 'property',
    \ '8': 'field',
    \ '9': 'constructor',
    \ '10': 'enum',
    \ '11': 'interface',
    \ '12': 'function',
    \ '13': 'variable',
    \ '14': 'constant',
    \ '15': 'string',
    \ '16': 'number',
    \ '17': 'boolean',
    \ '18': 'array',
    \ }

function! s:get_symbol_text_from_kind(kind)
    if has_key(s:symbol_kinds, a:kind)
        return s:symbol_kinds[a:kind]
    else
        return 'unknown symbol ' . a:kind
    endif
endfunction

function! s:lsp_symbols_to_loclist(symbols) abort
    let l:list = []
    for l:symbol in a:symbols
        let l:location = l:symbol.location
        if s:is_file_uri(l:location.uri)
            let l:path = s:uri_to_path(l:location.uri)
            let l:bufnr = bufnr(path)
            let l:line = l:location.range.start.line + 1
            call add(l:list, {
                \ 'filename': s:uri_to_path(l:location.uri),
                \ 'lnum': l:line,
                \ 'col': l:location.range.start.character + 1,
                \ 'text': s:get_symbol_text_from_kind(l:symbol.kind) . ' : ' . l:symbol.name
                \ })
        endif
    endfor
    return l:list
endfunction

function! s:start_lsp() abort
    if s:lsp_id <= 0
        let l:root_uri = ''
        if !exists('*s:get_root_uri_for_' . &ft) || !exists('*s:get_lsp_server_cmd_for_' . &ft)
            echom 'Language server protocol server not defined for ' . &ft
            return
        endif
        call execute('let l:cmd = s:get_lsp_server_cmd_for_' . &ft . '()')
        call execute('let l:root_uri = s:get_root_uri_for_' . &ft . '()')
        if !empty(l:root_uri) && !empty(l:cmd)
            let s:lsp_id = lsp#client#start({
                \ 'cmd': l:cmd,
                \ 'on_stderr': function('s:on_stderr'),
                \ 'on_exit': function('s:on_exit'),
                \ })
            if s:lsp_id > 0
                let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
                    \ 'method': 'initialize',
                    \ 'params': {
                    \   'capabilities': {},
                    \   'rootPath': l:root_uri,
                    \   'rootUri': l:root_uri,
                    \ },
                    \ 'on_notification': function('s:on_initialize')
                    \ })
            else
                echom 'Failed to start language server'
            endif
        else
            echom 'Failed to start language server. ' . json_encode({'root_uri': l:root_uri, 'cmd': l:cmd})
        endif
    endif
endfunction

function! s:on_notification_log(id, data, event) abort
    " echom json_encode(a:data)
endfunction

function! s:on_stderr(id, data, event) abort
    call s:on_notification_log(a:id, a:data, a:event)
endfunction

function! s:on_exit(id, status, event) abort
    echom 'language server exited with code ' . a:status . '. Try uncommenting s:on_stderr to see more details'
endfunction

function! s:on_initialize(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        let s:lsp_init_response = {}
    else
        let s:lsp_init_capabilities = a:data.response.result.capabilities
        if s:lsp_last_request_id > 0
            " javascript-typescript-langserver doesn't support this method so don't call it for now
            if &ft != 'typescript'
                let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
                    \ 'method': 'textDocument/didOpen',
                    \ 'params': {
                    \   'textDocument': s:get_text_document(),
                    \ },
                    \ 'on_notification': function('s:on_notification_log')
                    \ })
            endif
        endif
    endif
endfunction

function! s:goto_definition() abort
    if !s:supports_capability('definitionProvider')
        echom 'Go to definition not supported by the language server'
        return
    endif
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'textDocument/definition',
        \ 'params': {
        \   'textDocument': s:get_text_document_identifier(),
        \   'position': s:get_position(),
        \ },
        \ 'on_notification': function('s:on_goto_definition')
        \})
endfunction

function! s:on_goto_definition(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        echom 'error occurred going to definition'. json_encode(a:data)
        return
    endif
    if !has_key(a:data.response, 'result')  || len(a:data.response.result) == 0
        echom 'no results found'
        return
    endif
    let l:def = a:data.response.result[0]
    if s:is_file_uri(l:def.uri)
        if s:escape_path(expand('%:p') == s:escape_path(s:uri_to_path(l:def.uri)))
            call cursor(l:def.range.start.line + 1, l:def.range.start.character + 1)
        else
            execute 'edit +call\ cursor('.(l:def.range.start.line + 1).','.(l:def.range.start.character + 1).') '.s:uri_to_path(l:def.uri)
        endif
    else
        echom l:def.uri
    endif
endfunction

function! s:hover() abort
    if !s:supports_capability('hoverProvider')
        echom 'Hover not supported by the language server'
        return
    endif
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'textDocument/hover',
        \ 'params': {
        \   'textDocument': s:get_text_document_identifier(),
        \   'position': s:get_position(),
        \ },
        \ 'on_notification': function('s:on_hover')
        \})
endfunction

function! s:on_hover(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        echom 'error occurred going getting hover information '. json_encode(a:data)
        return
    endif
    if !has_key(a:data.response, 'result')  || len(a:data.response.result) == 0
        echom 'no hover result found'
        return
    endif
    let l:response = []
    for l:content in a:data.response.result.contents
        if type(l:content) == v:t_string
            let l:response += [l:content]
        else
            let l:response += [l:content.value]
        endif
    endfor
    echom join(l:response, "\n")
endfunction

function! s:find_references() abort
    if !s:supports_capability('referencesProvider')
        echom 'FindReferences not supported by the language server'
        return
    endif
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'textDocument/references',
        \ 'params': s:get_reference_params(),
        \ 'on_notification': function('s:on_find_references')
        \})
endfunction

function! s:on_find_references(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        echom 'error occurred finding references'. json_encode(a:data)
        return
    endif
    if !has_key(a:data.response, 'result')  || len(a:data.response.result) == 0
        echom 'no references found'
        return
    endif

    let l:locations = []
    for l:location in a:data.response.result
        if s:is_file_uri(l:location.uri)
            let l:path = s:uri_to_path(l:location.uri)
            let l:bufnr = bufnr(path)
            let l:line = l:location.range.start.line + 1
            call add(l:locations, {
                \ 'filename': s:uri_to_path(l:location.uri),
                \ 'lnum': l:line,
                \ 'col': l:location.range.start.character + 1,
                \ 'text': s:get_line_from_buf_or_file(l:bufnr, l:path, l:line)
                \ })
        endif
    endfor

    call setloclist(0, l:locations, 'r')

    if !empty(l:locations)
        lwindow
    endif
endfunction

function! s:find_document_symbols() abort
    if !s:supports_capability('documentSymbolProvider')
        echom 'FindDocumentSymbols not supported by the language server'
        return
    endif
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'textDocument/documentSymbol',
        \ 'params': {
        \   'textDocument': s:get_text_document_identifier(),
        \ },
        \ 'on_notification': function('s:on_find_document_symbols')
        \})
    echom 'Finding document symbols'
endfunction

function! s:on_find_document_symbols(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        echom 'error occurred finding document symbols'. json_encode(a:data)
        return
    endif

    if !has_key(a:data.response, 'result')  || len(a:data.response.result) == 0
        echom 'no document symbols found'
        return
    endif

    let l:locations = s:lsp_symbols_to_loclist(a:data.response.result)

    call setloclist(0, l:locations, 'r')

    if !empty(l:locations)
        lwindow
    endif
endfunction

function! s:find_workspace_symbols() abort
    if !s:supports_capability('workspaceSymbolProvider')
        echom 'FindWorkspaceSymbols not supported by the language server'
        return
    endif
    let l:query = input('query>')
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'workspace/symbol',
        \ 'params': {
        \   'query': l:query,
        \ },
        \ 'on_notification': function('s:on_find_workspace_symbols')
        \})
    echom 'Finding workspace symbols'
endfunction

function! s:on_find_workspace_symbols(id, data, event) abort
    if lsp#client#is_error(a:data.response)
        echom 'error occurred finding workspace symbols'. json_encode(a:data)
        return
    endif

    if !has_key(a:data.response, 'result')  || len(a:data.response.result) == 0
        echom 'no workspace symbols found'
        return
    endif

    let l:locations = s:lsp_symbols_to_loclist(a:data.response.result)

    call setloclist(0, l:locations, 'r')

    if !empty(l:locations)
        lwindow
    endif
endfunction

function! s:textdocument_did_save() abort
    if s:lsp_id <= 0 || empty(s:get_capabilities())
        return
    endif
    let s:lsp_last_request_id = lsp#client#send(s:lsp_id, {
        \ 'method': 'textDocument/didSave',
        \ 'params': {
        \   'textDocument': s:get_text_document_identifier(),
        \   'text': join(getline(1, '$'), "\n"),
        \ },
        \ 'on_notification': function('s:on_text_document_did_save')
        \})
endfunction

function! s:on_text_document_did_save(id, data, event) abort
    " do nothing
endfunction

function! s:get_capabilities() abort
    return s:lsp_init_capabilities
endfunction

function! s:supports_capability(name) abort
    let l:capabilities = s:get_capabilities()
    if !empty(l:capabilities) || has_key(l:capabilities, a:name)
        if type(l:capabilities[a:name]) == v:t_dict
            return 1
        elseif type(l:capabilities[a:name]) == v:t_bool && l:capabilities[a:name] == v:true
            return 1
        endif
    endif
    return 0
endfunction

command! GetCapabilities :echom json_encode(s:get_capabilities())
command! GoToDefinition call s:goto_definition()
command! Hover call s:hover()
command! FindReferences call s:find_references()
command! FindDocumentSymbols call s:find_document_symbols()
command! FindWorkspaceSymbols call s:find_workspace_symbols()

augroup lsp_ts
    autocmd!
    autocmd FileType typescript map <buffer> <C-]> :GoToDefinition<cr>
    autocmd FileType typescript map <buffer> <C-^> :FindReferences<cr>
    autocmd BufWinEnter,FileType * call s:start_lsp()
    autocmd BufWritePost,FileType * call s:textdocument_did_save()
augroup END
