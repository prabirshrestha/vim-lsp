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

function! s:symbols_to_loc_list_children(server, path, list, symbols, depth) abort
    for l:symbol in a:symbols
        let [l:line, l:col] = lsp#utils#position#lsp_to_vim(a:path, l:symbol['range']['start'])

        call add(a:list, {
            \ 'filename': a:path,
            \ 'lnum': l:line,
            \ 'col': l:col,
            \ 'text': lsp#ui#vim#utils#_get_symbol_text_from_kind(a:server, l:symbol['kind']) . ' : ' . printf('%' . a:depth. 's', '  ') . l:symbol['name'],
            \ })
        if has_key(l:symbol, 'children') && !empty(l:symbol['children'])
            call s:symbols_to_loc_list_children(a:server, a:path, a:list, l:symbol['children'], a:depth + 1)
        endif
    endfor
endfunction

function! lsp#ui#vim#utils#symbols_to_loc_list(server, result) abort
    if !has_key(a:result['response'], 'result')
        return []
    endif

    let l:list = []

    let l:locations = type(a:result['response']['result']) == type({}) ? [a:result['response']['result']] : a:result['response']['result']

    if !empty(l:locations) " some servers also return null so check to make sure it isn't empty
        for l:symbol in a:result['response']['result']
            if has_key(l:symbol, 'location')
                let l:location = l:symbol['location']
                if lsp#utils#is_file_uri(l:location['uri'])
                    let l:path = lsp#utils#uri_to_path(l:location['uri'])
                    let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, l:location['range']['start'])
                    call add(l:list, {
                        \ 'filename': l:path,
                        \ 'lnum': l:line,
                        \ 'col': l:col,
                        \ 'text': lsp#ui#vim#utils#_get_symbol_text_from_kind(a:server, l:symbol['kind']) . ' : ' . l:symbol['name'],
                        \ })
                endif
            else
                let l:location = a:result['request']['params']['textDocument']['uri']
                if lsp#utils#is_file_uri(l:location)
                    let l:path = lsp#utils#uri_to_path(l:location)
                    let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, l:symbol['range']['start'])
                    call add(l:list, {
                        \ 'filename': l:path,
                        \ 'lnum': l:line,
                        \ 'col': l:col,
                        \ 'text': lsp#ui#vim#utils#_get_symbol_text_from_kind(a:server, l:symbol['kind']) . ' : ' . l:symbol['name'],
                        \ })
                    if has_key(l:symbol, 'children') && !empty(l:symbol['children'])
                        call s:symbols_to_loc_list_children(a:server, l:path, l:list, l:symbol['children'], 1)
                    endif
                endif
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
    let l:diagnostics = lsp#utils#iteratable(a:result['response']['params']['diagnostics'])

    let l:list = []

    if !empty(l:diagnostics) && lsp#utils#is_file_uri(l:uri)
        let l:path = lsp#utils#uri_to_path(l:uri)
        for l:item in l:diagnostics
            let l:severity_text = ''
            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:severity_text = s:get_diagnostic_severity_text(l:item['severity'])
            endif
            let l:text = ''
            if has_key(l:item, 'source') && !empty(l:item['source'])
                let l:text .= l:item['source'] . ':'
            endif
            if l:severity_text !=# ''
                let l:text .= l:severity_text . ':'
            endif
            if has_key(l:item, 'code') && !empty(l:item['code'])
                let l:text .= l:item['code'] . ':'
            endif
            let l:text .= l:item['message']
            let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, l:item['range']['start'])
            let l:location_item = {
                \ 'filename': l:path,
                \ 'lnum': l:line,
                \ 'col': l:col,
                \ 'text': l:text,
                \ }
            if l:severity_text !=# ''
                " 'E' for error, 'W' for warning, 'I' for information, 'H' for hint
                let l:location_item['type'] = l:severity_text[0]
            endif
            call add(l:list, l:location_item)
        endfor
    endif

    return l:list
endfunction

function! lsp#ui#vim#utils#_get_symbol_text_from_kind(server, kind) abort
    if !has_key(s:symbol_kinds, a:server)
        let l:server_info = lsp#get_server_info(a:server)
        if has_key (l:server_info, 'config') && has_key(l:server_info['config'], 'symbol_kinds')
            let s:symbol_kinds[a:server] = extend(copy(s:default_symbol_kinds), l:server_info['config']['symbol_kinds'])
        else
            let s:symbol_kinds[a:server] = s:default_symbol_kinds
        endif
    endif
    return get(s:symbol_kinds[a:server], a:kind, 'unknown symbol ' . a:kind)
endfunction

function! lsp#ui#vim#utils#get_symbol_kinds() abort
    return map(keys(s:default_symbol_kinds), {idx, key -> str2nr(key)})
endfunction

function! s:get_diagnostic_severity_text(severity) abort
    return s:diagnostic_severity[a:severity]
endfunction
