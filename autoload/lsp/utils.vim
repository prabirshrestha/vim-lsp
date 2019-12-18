function! lsp#utils#is_remote_uri(uri) abort
    return a:uri =~# '^\w\+::' || a:uri =~# '^\w\+://'
endfunction

function! s:decode_uri(uri) abort
    let l:ret = substitute(a:uri, '[?#].*', '', '')
    return substitute(l:ret, '%\(\x\x\)', '\=printf("%c", str2nr(submatch(1), 16))', 'g')
endfunction

function! s:urlencode_char(c) abort
    return printf('%%%02X', char2nr(a:c))
endfunction

function! s:get_prefix(path) abort
    return matchstr(a:path, '\(^\w\+::\|^\w\+://\)')
endfunction

function! s:encode_uri(path, start_pos_encode, default_prefix) abort
    let l:prefix = s:get_prefix(a:path)
    let l:path = a:path[len(l:prefix):]
    if len(l:prefix) == 0
        let l:prefix = a:default_prefix
    endif

    let l:result = strpart(a:path, 0, a:start_pos_encode)

    for i in range(a:start_pos_encode, len(l:path) - 1)
        " Don't encode '/' here, `path` is expected to be a valid path.
        if l:path[i] =~# '^[a-zA-Z0-9_.~/-]$'
            let l:result .= l:path[i]
        else
            let l:result .= s:urlencode_char(l:path[i])
        endif
    endfor

    return l:prefix . l:result
endfunction

if has('win32') || has('win64')
    function! lsp#utils#path_to_uri(path) abort
        if empty(a:path)
            return a:path
        else
            " You must not encode the volume information on the path if
            " present
            let l:end_pos_volume = matchstrpos(a:path, '\c[A-Z]:')[2]

            if l:end_pos_volume == -1
                let l:end_pos_volume = 0
            endif

            return s:encode_uri(substitute(a:path, '\', '/', 'g'), l:end_pos_volume, 'file:///')
        endif
    endfunction
else
    function! lsp#utils#path_to_uri(path) abort
        if empty(a:path)
            return a:path
        else
            return s:encode_uri(a:path, 0, 'file://')
        endif
    endfunction
endif

if has('win32') || has('win64')
    function! lsp#utils#uri_to_path(uri) abort
        return substitute(s:decode_uri(a:uri[len('file:///'):]), '/', '\\', 'g')
    endfunction
else
    function! lsp#utils#uri_to_path(uri) abort
        return s:decode_uri(a:uri[len('file://'):])
    endfunction
endif

function! lsp#utils#get_default_root_uri() abort
    return lsp#utils#path_to_uri(getcwd())
endfunction

function! lsp#utils#get_buffer_path(...) abort
    return expand((a:0 > 0 ? '#' . a:1 : '%') . ':p')
endfunction

function! lsp#utils#get_buffer_uri(...) abort
    return lsp#utils#path_to_uri(expand((a:0 > 0 ? '#' . a:1 : '%') . ':p'))
endfunction

" Find a nearest to a `path` parent directory `directoryname` by traversing the filesystem upwards
function! lsp#utils#find_nearest_parent_directory(path, directoryname) abort
    let l:relative_path = finddir(a:directoryname, a:path . ';')

    if !empty(l:relative_path)
        return fnamemodify(l:relative_path, ':p')
    else
        return ''
    endif
endfunction

" Find a nearest to a `path` parent filename `filename` by traversing the filesystem upwards
function! lsp#utils#find_nearest_parent_file(path, filename) abort
    let l:relative_path = findfile(a:filename, a:path . ';')

    if !empty(l:relative_path)
        return fnamemodify(l:relative_path, ':p')
    else
        return ''
    endif
endfunction

" Find a nearest to a `path` parent filename `filename` by traversing the filesystem upwards
" The filename ending with '/' or '\' will be regarded as directory name,
" otherwith as file name
function! lsp#utils#find_nearest_parent_file_directory(path, filename) abort
    if type(a:filename) == 3
        let l:matched_paths = {}
        for current_name in a:filename
            let l:path = lsp#utils#find_nearest_parent_file_directory(a:path, current_name)

            if !empty(l:path)
                if has_key(l:matched_paths, l:path)
                    let l:matched_paths[l:path] += 1
                else
                    let l:matched_paths[l:path] = 1
                endif
            endif
        endfor
        return empty(l:matched_paths) ? 
                    \ '' : 
                    \ keys(l:matched_paths)[index(values(l:matched_paths), max(values(l:matched_paths)))]

    elseif type(a:filename) == 1
        if a:filename[-1:] ==# '/' || a:filename[-1:] ==# '\'
            let l:modify_str = ':p:h:h'
            let l:path = lsp#utils#find_nearest_parent_directory(a:path, a:filename[:-2])
        else
            let l:modify_str = ':p:h'
            let l:path = lsp#utils#find_nearest_parent_file(a:path, a:filename)
        endif

        return empty(l:path) ? '' : fnamemodify(l:path, l:modify_str)
    else
        echoerr "The type of argument \"filename\" must be String or List"
    endif
endfunction

if exists('*matchstrpos')
    function! lsp#utils#matchstrpos(expr, pattern) abort
        return matchstrpos(a:expr, a:pattern)
    endfunction
else
    function! lsp#utils#matchstrpos(expr, pattern) abort
        return [matchstr(a:expr, a:pattern), match(a:expr, a:pattern), matchend(a:expr, a:pattern)]
    endfunction
endif

function! lsp#utils#empty_complete(...) abort
    return []
endfunction

function! lsp#utils#error(msg) abort
    echohl ErrorMsg
    echom a:msg
    echohl NONE
endfunction

function! lsp#utils#echo_with_truncation(msg) abort
    let l:msg = a:msg

    if &laststatus == 0 || (&laststatus == 1 && tabpagewinnr(tabpagenr(), '$') == 1)
        let l:winwidth = winwidth(0)

        if &ruler
            let l:winwidth -= 18
        endif
    else
        let l:winwidth = &columns
    endif

    if &showcmd
        let l:winwidth -= 12
    endif

    if l:winwidth > 5 && l:winwidth < strdisplaywidth(l:msg)
        let l:msg = l:msg[:l:winwidth - 5] . '...'
    endif

    exec 'echo l:msg'
endfunction

" Convert a character-index (0-based) to byte-index (1-based)
" This function requires a buffer specifier (expr, see :help bufname()),
" a line number (lnum, 1-based), and a character-index (char, 0-based).
function! lsp#utils#to_col(expr, lnum, char) abort
    let l:lines = getbufline(a:expr, a:lnum)
    if l:lines == []
        if type(a:expr) != v:t_string || !filereadable(a:expr)
            " invalid a:expr
            return a:char + 1
        endif
        " a:expr is a file that is not yet loaded as a buffer
        let l:lines = readfile(a:expr, '', a:lnum)
    endif
    let l:linestr = l:lines[-1]
    return strlen(strcharpart(l:linestr, 0, a:char)) + 1
endfunction

" Convert a byte-index (1-based) to a character-index (0-based)
" This function requires a buffer specifier (expr, see :help bufname()),
" a line number (lnum, 1-based), and a byte-index (char, 1-based).
function! lsp#utils#to_char(expr, lnum, col) abort
    let l:lines = getbufline(a:expr, a:lnum)
    if l:lines == []
        if type(a:expr) != v:t_string || !filereadable(a:expr)
            " invalid a:expr
            return a:col - 1
        endif
        " a:expr is a file that is not yet loaded as a buffer
        let l:lines = readfile(a:expr, '', a:lnum)
    endif
    let l:linestr = l:lines[-1]
    return strchars(strpart(l:linestr, 0, a:col - 1))
endfunction
