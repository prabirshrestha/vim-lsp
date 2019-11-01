function! lsp#ui#vim#utils#locations_to_loc_list(result) abort
    if !has_key(a:result['response'], 'result')
        return []
    endif

    let l:list = []

    let l:locations = type(a:result['response']['result']) == type({}) ? [a:result['response']['result']] : a:result['response']['result']

    if empty(l:locations) " some servers also return null so check to make sure it isn't empty
        return []
    endif

    if has_key(l:locations[0],'targetUri') " server returns locationLinks
        let l:use_link = 1
        let l:uri = 'targetUri'
        let l:range = 'targetSelectionRange'
    else
        let l:use_link = 0
        let l:uri = 'uri'
        let l:range = 'range'
    endif

    let l:cache={}
    for l:location in l:locations
        if s:is_file_uri(l:location[l:uri])
            let l:path = lsp#utils#uri_to_path(l:location[l:uri])
            let l:line = l:location[l:range]['start']['line'] + 1
            let l:char = l:location[l:range]['start']['character']
            let l:col = lsp#utils#to_col(l:path, l:line, l:char)

            let l:index = l:line - 1
            if has_key(l:cache, l:path)
                let l:text = l:cache[l:path][l:index]
            else
                let l:contents = getbufline(l:path, 1, '$')
                if !empty(l:contents)
                    let l:text = l:contents[l:index]
                else
                    let l:contents = readfile(l:path)
                    let l:cache[l:path] = l:contents
                    let l:text = l:contents[l:index]
                endif
            endif
            if l:use_link
                let l:viewstart = l:location['targetRange']['start']['line']
                let l:viewend = l:location['targetRange']['end']['line']
                call add(l:list, {
                            \ 'filename': l:path,
                            \ 'lnum': l:line,
                            \ 'col': l:col,
                            \ 'text': l:text,
                            \ 'viewstart': l:viewstart,
                            \ 'viewend': l:viewend
                            \ })
            else
                call add(l:list, {
                            \ 'filename': l:path,
                            \ 'lnum': l:line,
                            \ 'col': l:col,
                            \ 'text': l:text,
                            \ })
            endif
        endif
    endfor

    return l:list
endfunction

let s:default_symbol_kinds = {
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
    \ '19': 'object',
    \ '20': 'key',
    \ '21': 'null',    
    \ '22': 'enum member',    
    \ '23': 'struct',    
    \ '24': 'event',    
    \ '25': 'operator',    
    \ '26': 'type parameter',    
    \ }

let s:symbol_kinds = {}

let s:diagnostic_severity = {
    \ 1: 'Error',
    \ 2: 'Warning',
    \ 3: 'Information',
    \ 4: 'Hint',
    \ }

function! lsp#ui#vim#utils#symbols_to_loc_list(server, result) abort
    if !has_key(a:result['response'], 'result')
        return []
    endif

    let l:list = []

    let l:locations = type(a:result['response']['result']) == type({}) ? [a:result['response']['result']] : a:result['response']['result']

    if !empty(l:locations) " some servers also return null so check to make sure it isn't empty
        for l:symbol in a:result['response']['result']
            let l:location = l:symbol['location']
            if s:is_file_uri(l:location['uri'])
                let l:path = lsp#utils#uri_to_path(l:location['uri'])
                let l:bufnr = bufnr(l:path)
                let l:line = l:location['range']['start']['line'] + 1
                let l:char = l:location['range']['start']['character']
                let l:col = lsp#utils#to_col(l:path, l:line, l:char)
                call add(l:list, {
                    \ 'filename': l:path,
                    \ 'lnum': l:line,
                    \ 'col': l:col,
                    \ 'text': s:get_symbol_text_from_kind(a:server, l:symbol['kind']) . ' : ' . l:symbol['name'],
                    \ })
            endif
        endfor
    endif

    return l:list
endfunction

function! lsp#ui#vim#utils#diagnostics_to_loc_list(result) abort
    if !has_key(a:result['response'], 'params')
        return
    endif

    let l:uri = a:result['response']['params']['uri']
    let l:diagnostics = a:result['response']['params']['diagnostics']

    let l:list = []

    if !empty(l:diagnostics) && s:is_file_uri(l:uri)
        let l:path = lsp#utils#uri_to_path(l:uri)
        let l:bufnr = bufnr(l:path)
        for l:item in l:diagnostics
            let l:text = ''
            if has_key(l:item, 'source') && !empty(l:item['source'])
                let l:text .= l:item['source'] . ':'
            endif
            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:text .= s:get_diagnostic_severity_text(l:item['severity']) . ':'
            endif
            if has_key(l:item, 'code') && !empty(l:item['code'])
                let l:text .= l:item['code'] . ':'
            endif
            let l:text .= l:item['message']
            let l:line = l:item['range']['start']['line'] + 1
            let l:char = l:item['range']['start']['character']
            let l:col = lsp#utils#to_col(l:path, l:line, l:char)
            call add(l:list, {
                \ 'filename': l:path,
                \ 'lnum': l:line,
                \ 'col': l:col,
                \ 'text': l:text,
                \ })
        endfor
    endif

    return l:list
endfunction

function! s:is_file_uri(uri) abort
    return stridx(a:uri, 'file:///') == 0
endfunction

function! s:get_symbol_text_from_kind(server, kind) abort
    if !has_key(s:symbol_kinds, a:server)
        let l:server_info = lsp#get_server_info(a:server)
        if has_key (l:server_info, 'config') && has_key(l:server_info['config'], 'symbol_kinds')
            let s:symbol_kinds[a:server] = extend(copy(s:default_symbol_kinds), l:server_info['config']['symbol_kinds'])
        else
            let s:symbol_kinds[a:server] = s:default_symbol_kinds
        endif
    endif
    let l:symbol_kinds = s:symbol_kinds[a:server]
    return has_key(l:symbol_kinds, a:kind) ? l:symbol_kinds[a:kind] : 'unknown symbol ' . a:kind
endfunction

function! lsp#ui#vim#utils#get_symbol_kinds() abort
    return map(keys(s:default_symbol_kinds), {idx, key -> str2nr(key)})
endfunction

function! s:get_diagnostic_severity_text(severity) abort
    return s:diagnostic_severity[a:severity]
endfunction
