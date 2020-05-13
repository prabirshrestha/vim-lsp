let s:tag_kind_priority = ['definition', 'declaration', 'implementation', 'type definition']

function! s:not_supported(what) abort
    call lsp#log(a:what . ' not supported for ' . &filetype)
endfunction

" polyfill for the neovim wait function
function! s:wait(timeout, condition, ...) abort
    if exists('*wait')
        return call('wait', extend([a:timeout, a:condition], a:000))
    endif

    try
        let l:timeout = a:timeout / 1000.0
        let l:interval = get(a:000, 0, 200)
        let l:Condition = a:condition
        if type(l:Condition) != v:t_func
            let l:Condition = function('eval', l:Condition)
        endif
        let l:start = reltime()
        while l:timeout < 0 || reltimefloat(reltime(l:start)) < l:timeout
            if l:Condition()
                return 0
            endif

            execute 'sleep ' . l:interval . 'm'
        endwhile
        return -1
    catch /^Vim:Interrupt$/
        return -2
    endtry
endfunction

function! s:location_to_tag(loc) abort
    if has_key(a:loc, 'targetUri')
        let l:uri = a:loc['targetUri']
        let l:range = a:loc['targetRange']
    else
        let l:uri = a:loc['uri']
        let l:range = a:loc['range']
    endif

    if !lsp#utils#is_file_uri(l:uri)
        return v:null
    endif

    return {
        \ 'filename': lsp#utils#uri_to_path(l:uri),
        \ 'cmd': string(l:range['start']['line'] + 1)
        \ }
endfunction

function! s:handle_locations(ctx, server, type, data) abort
    try
        if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
            call lsp#utils#error('Failed to retrieve ' . a:type . ' for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
            return
        endif

        let l:list = a:ctx['list']
        let l:result = a:data['response']['result']
        if type(l:result) != v:t_list
            let l:result = [l:result]
        endif
        for l:loc in l:result
            let l:tag = s:location_to_tag(l:loc)
            if !empty(l:tag)
                call add(l:list, extend(l:tag, { 'name': a:ctx['pattern'], 'kind': a:type }))
            endif
        endfor
    finally
        let a:ctx['counter'] -= 1
    endtry
endfunction

function! s:handle_symbols(ctx, server, data) abort
    try
        if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
            call lsp#utils#error('Failed to retrieve workspace symbols for ' . a:server . ': ' . lsp#client#error_message(a:data['response']))
            return
        endif

        let l:list = a:ctx['list']
        for l:symbol in a:data['response']['result']
            let l:tag = s:location_to_tag(l:symbol['location'])
            if empty(l:tag)
                continue
            endif

            let l:tag['name'] = l:symbol['name']
            if has_key(l:symbol, 'kind')
                let l:tag['kind'] = lsp#ui#vim#utils#get_symbol_text_from_kind(a:server, l:symbol['kind'])
            endif
            call add(l:list, l:tag)
        endfor
    finally
        let a:ctx['counter'] -= 1
    endtry
endfunction

function! s:tag_view_sub(ctx, method, params) abort
    let l:operation = substitute(a:method, '\u', ' \l\0', 'g')

    let l:capabilities_func = printf('lsp#capabilities#has_%s_provider(v:val)', substitute(l:operation, ' ', '_', 'g'))
    let l:servers = filter(lsp#get_whitelisted_servers(), l:capabilities_func)
    if empty(l:servers)
        call s:not_supported('retrieving ' . l:operation)
        return v:false
    endif

    let a:ctx['counter'] += len(l:servers)
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/'.a:method,
            \ 'params': a:params,
            \ 'on_notification': function('s:handle_locations', [a:ctx, l:server, l:operation])
            \})
    endfor
    return v:true
endfunction

function! s:tag_view(ctx) abort
    let l:params = {
        \ 'textDocument': lsp#get_text_document_identifier(),
        \ 'position': lsp#get_position(),
        \ }
    return !empty(filter(copy(g:lsp_tagfunc_source_methods),
        \ {_, m -> s:tag_view_sub(a:ctx, m, l:params)}))
endfunction

function! s:tag_search(ctx) abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    if empty(l:servers)
        call s:not_supported('retrieving workspace symbols')
        return v:false
    endif

    let a:ctx['counter'] = len(l:servers)
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'workspace/symbol',
            \ 'params': { 'query': a:ctx['pattern'] },
            \ 'on_notification': function('s:handle_symbols', [a:ctx, l:server])
            \ })
    endfor
    return v:true
endfunction

function! s:compare_tags(path, a, b) abort
    " TODO: custom tag sorting, maybe?
    if a:a['filename'] !=# a:b['filename']
        if a:a['filename'] ==# a:path
            return -1
        elseif a:b['filename'] ==# a:path
            return 1
        endif
    endif
    let l:rank_a = index(s:tag_kind_priority, get(a:a, 'kind', ''))
    let l:rank_b = index(s:tag_kind_priority, get(a:b, 'kind', ''))
    if l:rank_a != l:rank_b
        return l:rank_a < l:rank_b ? -1 : 1
    endif
    if a:a['filename'] !=# a:b['filename']
        return a:a['filename'] <# a:b['filename'] ? -1 : 1
    endif
    return str2nr(a:a['cmd']) - str2nr(a:b['cmd'])
endfunction

function! lsp#tag#tagfunc(pattern, flags, info) abort
    if stridx(a:flags, 'i') >= 0
        return v:null
    endif

    let l:ctx = { 'pattern': a:pattern, 'counter': 0, 'list': [] }
    if !(stridx(a:flags, 'c') >= 0 ? s:tag_view(l:ctx) : s:tag_search(l:ctx))
        " No supported methods so use builtin tag source
        return v:null
    endif
    while s:wait(-1, {-> l:ctx['counter'] == 0}) == -3
        continue " ignore spurious internal error
    endwhile
    call sort(l:ctx['list'], function('s:compare_tags', [a:info['buf_ffname']]))
    return l:ctx['list']
endfunction
