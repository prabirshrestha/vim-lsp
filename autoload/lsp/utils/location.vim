function! s:open_location(path, line, col, ...) abort
    normal! m'
    let l:mods = a:0 ? a:1 : ''
    let l:buffer = bufnr(a:path)
    if l:mods ==# '' && &modified && !&hidden && l:buffer != bufnr('%')
        let l:mods = &splitbelow ? 'rightbelow' : 'leftabove'
    endif
    if l:mods ==# ''
        if l:buffer == bufnr('%')
            let l:cmd = ''
        else
            let l:cmd = (l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . fnameescape(a:path)) . ' | '
        endif
    else
        let l:cmd = l:mods . ' ' . (l:buffer !=# -1 ? 'sb ' . l:buffer : 'split ' . fnameescape(a:path)) . ' | '
    endif
    execute l:cmd . 'call cursor('.a:line.','.a:col.')'
endfunction

" @param location = {
"   'filename',
"   'lnum',
"   'col',
" }
function! lsp#utils#location#_open_vim_list_item(location, mods) abort
    call s:open_location(a:location['filename'], a:location['lnum'], a:location['col'], a:mods)
endfunction

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

    let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim(l:bufnr, a:location['range']['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim(l:bufnr, a:location['range']['end'])

    call s:open_location(l:path, l:start_line, l:start_col)

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
"   'text',
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
    let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, l:range['start'])

    let l:index = l:line - 1
    if has_key(a:cache, l:path)
        let l:text = a:cache[l:path][l:index]
    else
        let l:contents = getbufline(l:path, 1, '$')
        if !empty(l:contents)
            let l:text = get(l:contents, l:index, '')
        else
            let l:contents = readfile(l:path)
            let a:cache[l:path] = l:contents
            let l:text = get(l:contents, l:index, '')
        endif
    endif

    if l:use_link
        " viewstart/end decremented to account for incrementing in _lsp_to_vim
        return {
            \ 'filename': l:path,
            \ 'lnum': l:line,
            \ 'col': l:col,
            \ 'text': l:text,
            \ 'viewstart': lsp#utils#position#lsp_to_vim(l:path, a:loc['targetRange']['start'])[0] - 1,
            \ 'viewend': lsp#utils#position#lsp_to_vim(l:path, a:loc['targetRange']['end'])[0] - 1,
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

" @summary Use this to convert loc to vim list that is compatible with
" quickfix and locllist items
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
        let l:vim_loc = s:lsp_location_item_to_vim(a:loc, l:cache)
        if !empty(l:vim_loc) " https:// uri will return empty
            call add(l:result, l:vim_loc)
        endif
    endif
    return l:result
endfunction
