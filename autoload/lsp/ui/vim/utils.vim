function! lsp#ui#vim#utils#locations_to_loc_list(result) abort
    if !has_key(a:result['response'], 'result')
        return []
    endif

    let l:list = []

    let l:locations = type(a:result['response']['result']) == type({}) ? [a:result['response']['result']] : a:result['response']['result']

    if !empty(l:locations) " some servers also return null so check to make sure it isn't empty
        for l:location in l:locations
            if s:is_file_uri(l:location['uri'])
                let l:path = lsp#utils#uri_to_path(l:location['uri'])
                let l:line = l:location['range']['start']['line'] + 1
                let l:col = l:location['range']['start']['character'] + 1
                let l:text = bufnr(l:path) ==# -1 ? 'File not loaded' : getbufline(bufnr(l:path), l:line)[0]
                call add(l:list, {
                    \ 'filename': l:path,
                    \ 'lnum': l:line,
                    \ 'col': l:col,
                    \ 'text': l:text,
                    \ })
            endif
        endfor
    endif

    return l:list
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

let s:diagnostic_severity = {
    \ 1: 'Error',
    \ 2: 'Warning',
    \ 3: 'Information',
    \ 4: 'Hint',
    \ }

function! lsp#ui#vim#utils#symbols_to_loc_list(result) abort
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
                let l:col = l:location['range']['start']['character'] + 1
                call add(l:list, {
                    \ 'filename': l:path,
                    \ 'lnum': l:line,
                    \ 'col': l:col,
                    \ 'text': s:get_symbol_text_from_kind(l:symbol['kind']) . ' : ' . l:symbol['name'],
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
            let l:col = l:item['range']['start']['character'] + 1
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

function! s:get_symbol_text_from_kind(kind) abort
    return has_key(s:symbol_kinds, a:kind) ? s:symbol_kinds[a:kind] : 'unknown symbol ' . a:kind
endfunction

function! s:get_diagnostic_severity_text(severity) abort
    return s:diagnostic_severity[a:severity]
endfunction
