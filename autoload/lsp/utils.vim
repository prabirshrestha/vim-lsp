function! lsp#utils#is_remote_uri(uri) abort
    return a:uri =~# '^\w\+::' || a:uri =~# '^\w\+://'
endfunction

if has('win32') || has('win64')
    function! lsp#utils#path_to_uri(path) abort
        if empty(a:path)
            return a:path
        else
            return lsp#utils#is_remote_uri(a:path) ? a:path : 'file:///' . substitute(a:path, '\', '/', 'g')
        endif
    endfunction
else
    function! lsp#utils#path_to_uri(path) abort
        if empty(a:path)
            return a:path
        else
            return lsp#utils#is_remote_uri(a:path) ? a:path : 'file://' . a:path
        endif
    endfunction
endif

if has('win32') || has('win64')
    function! lsp#utils#uri_to_path(uri) abort
        return substitute(a:uri[len('file:///'):], '/', '\\', 'g')
    endfunction
else
    function! lsp#utils#uri_to_path(uri) abort
        return a:uri[len('file://'):]
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
function! lsp#utils#find_nearest_parent_file_directory(path, filename) abort
    let l:path = lsp#utils#find_nearest_parent_file(a:path, a:filename)

    if !empty(l:path)
        return fnamemodify(l:path, ':p:h')
    else
        return ''
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
