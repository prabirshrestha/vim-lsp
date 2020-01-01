" @params {location} = {
"   'uri': 'file://....',
"   'range': {
"       'start': { 'line': 1, 'character': 1 },
"       'end': { 'line': 1, 'character': 1 },
"   }
" }
function! lsp#utils#location#_open_lsp_location(location) abort
    let l:path = lsp#utils#uri_to_path(a:location['uri'])
    let l:bufnr = bufnr(l:path)

    let [l:start_line, l:start_col] = lsp#utils#position#_lsp_to_vim(l:bufnr, a:location['range']['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#_lsp_to_vim(l:bufnr, a:location['range']['end'])

    normal! m'
    if &modified && !&hidden
        let l:cmd = l:bufnr !=# -1 ? 'sb ' . l:bufnr : 'split ' . fnameescape(l:path)
    else
        let l:cmd = l:bufnr !=# -1 ? 'b ' . l:bufnr : 'edit ' . fnameescape(l:path)
    endif
    execute l:cmd . ' | call cursor('.l:start_line.','.l:start_col.')'

    let l:bufnr = bufnr('%')
    normal! V
    call setpos("'<", [l:bufnr, l:start_line, l:start_col])
    call setpos("'>", [l:bufnr, l:end_line, l:end_col])
endfunction

" @param loc = Location | LocationLink
" @param cache = {} empty dict
" @returns {
"   'filename',
"   'lnum',
"   'col',
"   'viewstart?',
"   'viewend?',
" }
function! s:lsp_location_item_to_vim(loc, cache) abort
    if has_key(a:loc, 'targetUri') " LocationLink
        let l:uri = a:loc['targetUri']
        let l:range = a:loc['targetSelectionRange']
        let l:use_link = 1
    else " Location
        let l:uri = a:loc['uri']
        let l:range = a:loc['range']
        let l:use_link = 0
    endif

    if !lsp#utils#is_file_uri(l:uri)
        return v:null
    endif

    let l:path = lsp#utils#uri_to_path(l:uri)
    let [l:line, l:col] = lsp#utils#position#_lsp_to_vim(l:path, l:range['start'])

    let l:index = l:line - 1
    if has_key(a:cache, l:path)
        let l:text = a:cache[l:path][l:index]
    else
        let l:contents = getbufline(l:path, 1, '$')
        if !empty(l:contents)
            let l:text = l:contents[l:index]
        else
            let l:contents = readfile(l:path)
            let a:cache[l:path] = l:contents
            let l:text = l:contents[l:index]
        endif
    endif

    if l:use_link
        return {
            \ 'filename': l:path,
            \ 'lnum': l:line,
            \ 'col': l:col,
            \ 'text': l:text,
            \ 'viewstart': lsp#utils#position#_lsp_to_vim(l:path, a:loc['targetRange']['start'])[0],
            \ 'viewend': lsp#utils#position#_lsp_to_vim(l:path, a:loc['targetRange']['end'])[0],
            \ }
    else
        return {
            \ 'filename': l:path,
            \ 'lnum': l:line,
            \ 'col': l:col,
            \ 'text': l:text,
            \ }
    endif
endfunction

" @param loc = v:null | Location | Location[] | LocationLink
" @returns []
function! lsp#utils#location#_lsp_to_vim_list(loc) abort
    let l:result = []
    let l:cache = {}
    if empty(a:loc) " v:null
        return l:result
    elseif type(a:loc) == type([]) " Location[]
        for l:location in a:loc
            let l:vim_loc = s:lsp_location_item_to_vim(l:location, l:cache)
            if !empty(l:vim_loc) " https:// uri will return empty
                call add(l:result, l:vim_loc)
            endif
        endfor
    else " Location or LocationLink
        let l:vim_loc = s:lsp_location_item_to_vim(l:location, l:cache)
        if !empty(l:vim_loc) " https:// uri will return empty
            call add(l:result, l:vim_loc)
        endif
    endif
    return l:result
endfunction
