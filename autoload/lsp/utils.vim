function! lsp#utils#is_file_uri(uri) abort
    return stridx(a:uri, 'file:///') == 0
endfunction

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

    for l:i in range(a:start_pos_encode, len(l:path) - 1)
        " Don't encode '/' here, `path` is expected to be a valid path.
        if l:path[l:i] =~# '^[a-zA-Z0-9_.~/-]$'
            let l:result .= l:path[l:i]
        else
            let l:result .= s:urlencode_char(l:path[l:i])
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
        for l:current_name in a:filename
            let l:path = lsp#utils#find_nearest_parent_file_directory(a:path, l:current_name)

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

function! s:get_base64_alphabet() abort
    let l:alphabet = []

    " Uppercase letters
    for l:c in range(char2nr('A'), char2nr('Z'))
        call add(l:alphabet, nr2char(l:c))
    endfor

    " Lowercase letters
    for l:c in range(char2nr('a'), char2nr('z'))
        call add(l:alphabet, nr2char(l:c))
    endfor

    " Numbers
    for l:c in range(char2nr('0'), char2nr('9'))
        call add(l:alphabet, nr2char(l:c))
    endfor

    " Symbols
    call add(l:alphabet, '+')
    call add(l:alphabet, '/')

    return l:alphabet
endfunction

if exists('*trim')
  function! lsp#utils#_trim(string) abort
    return trim(a:string)
  endfunction
else
  function! lsp#utils#_trim(string) abort
    return substitute(a:string, '^\s*\|\s*$', '', 'g')
  endfunction
endif

function! lsp#utils#_get_before_line() abort
  let l:text = getline('.')
  let l:idx = min([strlen(l:text), col('.') - 2])
  let l:idx = max([l:idx, -1])
  if l:idx == -1
    return ''
  endif
  return l:text[0 : l:idx]
endfunction

function! lsp#utils#_get_before_char_skip_white() abort
  let l:current_lnum = line('.')

  let l:lnum = l:current_lnum
  while l:lnum > 0
    if l:lnum == l:current_lnum
      let l:text = lsp#utils#_get_before_line()
    else
      let l:text = getline(l:lnum)
    endif
    let l:match = matchlist(l:text, '\([^[:blank:]]\)\s*$')
    if get(l:match, 1, v:null) isnot v:null
      return l:match[1]
    endif
    let l:lnum -= 1
  endwhile

  return ''
endfunction

let s:alphabet = s:get_base64_alphabet()

function! lsp#utils#base64_decode(data) abort
    let l:ret = []

    " Process base64 string in chunks of 4 chars
    for l:group in split(a:data, '.\{4}\zs')
        let l:group_dec = 0

        " Convert 4 chars to 3 octets
        for l:char in split(l:group, '\zs')
            let l:group_dec = l:group_dec * 64
            let l:group_dec += max([index(s:alphabet, l:char), 0])
        endfor

        " Split the number representing the 3 octets into the individual
        " octets
        let l:octets = []
        let l:i = 0
        while l:i < 3
            call add(l:octets, l:group_dec % 256)
            let l:group_dec = l:group_dec / 256
            let l:i += 1
        endwhile

        call extend(l:ret, reverse(l:octets))
    endfor

    " Handle padding
    if len(a:data) >= 2
        if strpart(a:data, len(a:data) - 2) ==# '=='
            call remove(l:ret, -2, -1)
        elseif strpart(a:data, len(a:data) - 1) ==# '='
            call remove(l:ret, -1, -1)
        endif
    endif

    return l:ret
endfunction

function! lsp#utils#make_valid_word(str) abort
   let l:str = matchstr(a:str, '^[^ (<{\[\t\r\n]\+')
   if l:str =~# ':$'
     return l:str[:-2]
   endif
   return l:str
endfunction

function! lsp#utils#_split_by_eol(text) abort
    return split(a:text, '\r\n\|\r\|\n', v:true)
endfunction

