let s:has_lua = has('nvim-0.4.0') || (has('lua') && has('patch-8.2.0775'))
function! lsp#utils#has_lua() abort
    return s:has_lua
endfunction

let s:has_virtual_text = exists('*nvim_buf_set_virtual_text') && exists('*nvim_create_namespace')
function! lsp#utils#_has_virtual_text() abort
    return s:has_virtual_text
endfunction

let s:has_signs = exists('*sign_define') && (has('nvim') || has('patch-8.1.0772'))
function! lsp#utils#_has_signs() abort
    return s:has_signs
endfunction

let s:has_nvim_buf_highlight = exists('*nvim_buf_add_highlight')
function! lsp#utils#_has_nvim_buf_highlight() abort
    return s:has_nvim_buf_highlight
endfunction

" https://github.com/prabirshrestha/vim-lsp/issues/399#issuecomment-500585549
let s:has_textprops = exists('*prop_add') && has('patch-8.1.1035')
function! lsp#utils#_has_textprops() abort
    return s:has_textprops
endfunction

let s:has_higlights = has('nvim') ? lsp#utils#_has_nvim_buf_highlight() : lsp#utils#_has_textprops()
function! lsp#utils#_has_highlights() abort
    return s:has_higlights
endfunction

function! lsp#utils#is_file_uri(uri) abort
    return stridx(a:uri, 'file:///') == 0
endfunction

function! lsp#utils#is_remote_uri(uri) abort
    return a:uri =~# '^\w\+::' || a:uri =~# '^[a-z][a-z0-9+.-]*://'
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

let s:path_to_uri_cache = {}
if has('win32') || has('win64') || has('win32unix')
    function! lsp#utils#path_to_uri(path) abort
        if has_key(s:path_to_uri_cache, a:path)
            return s:path_to_uri_cache[a:path]
        endif

        if empty(a:path) || lsp#utils#is_remote_uri(a:path)
            let s:path_to_uri_cache[a:path] = a:path
            return s:path_to_uri_cache[a:path]
        else
            " Transform cygwin paths to windows paths
            let l:path = a:path
            if has('win32unix')
                let l:path = substitute(a:path, '\c^/\([a-z]\)/', '\U\1:/', '')
            endif

            " You must not encode the volume information on the path if
            " present
            let l:end_pos_volume = matchstrpos(l:path, '\c[A-Z]:')[2]

            if l:end_pos_volume == -1
                let l:end_pos_volume = 0
            endif

            let s:path_to_uri_cache[l:path] = s:encode_uri(substitute(l:path, '\', '/', 'g'), l:end_pos_volume, 'file:///')
            return s:path_to_uri_cache[l:path]
        endif
    endfunction
else
    function! lsp#utils#path_to_uri(path) abort
        if has_key(s:path_to_uri_cache, a:path)
            return s:path_to_uri_cache[a:path]
        endif

        if empty(a:path) || lsp#utils#is_remote_uri(a:path)
            let s:path_to_uri_cache[a:path] = a:path
            return s:path_to_uri_cache[a:path]
        else
            let s:path_to_uri_cache[a:path] = s:encode_uri(a:path, 0, 'file://')
            return s:path_to_uri_cache[a:path]
        endif
    endfunction
endif

let s:uri_to_path_cache = {}
if has('win32') || has('win64') || has('win32unix')
    function! lsp#utils#uri_to_path(uri) abort
        if has_key(s:uri_to_path_cache, a:uri)
            return s:uri_to_path_cache[a:uri]
        endif

        let l:path = substitute(s:decode_uri(a:uri[len('file:///'):]), '/', '\\', 'g')

        " Transform windows paths to cygwin paths
        if has('win32unix')
            let l:path = substitute(l:path, '\c^\([A-Z]\):\\', '/\l\1/', '')
            let l:path = substitute(l:path, '\\', '/', 'g')
        endif

        let s:uri_to_path_cache[a:uri] = l:path
        return s:uri_to_path_cache[a:uri]
    endfunction
else
    function! lsp#utils#uri_to_path(uri) abort
        if has_key(s:uri_to_path_cache, a:uri)
            return s:uri_to_path_cache[a:uri]
        endif

        let s:uri_to_path_cache[a:uri] = s:decode_uri(a:uri[len('file://'):])
        return s:uri_to_path_cache[a:uri]
    endfunction
endif

if has('win32') || has('win64')
    function! lsp#utils#normalize_uri(uri) abort
        " Refer to https://github.com/microsoft/language-server-protocol/pull/1019 on normalization of urls.
        " TODO: after the discussion is settled, modify this function.
        let l:ret = substitute(a:uri, '^file:///[a-zA-Z]\zs%3[aA]', ':', '')
        return substitute(l:ret, '^file:///\zs\([A-Z]\)', "\\=tolower(submatch(1))", '')
    endfunction
else
    function! lsp#utils#normalize_uri(uri) abort
        return a:uri
    endfunction
endif

function! lsp#utils#get_default_root_uri() abort
    return lsp#utils#path_to_uri(getcwd())
endfunction

function! lsp#utils#get_buffer_path(...) abort
    return expand((a:0 > 0 ? '#' . a:1 : '%') . ':p')
endfunction

function! lsp#utils#get_buffer_uri(...) abort
    let l:name = a:0 > 0 ? bufname(a:1) : expand('%')
    if empty(l:name)
        let l:nr = a:0 > 0 ? a:1 : bufnr('%')
        let l:name = printf('%s/__NO_NAME_%d__', getcwd(), l:nr)
    endif
    return lsp#utils#path_to_uri(fnamemodify(l:name, ':p'))
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

function! lsp#utils#_compare_nearest_path(matches, lhs, rhs) abort
  let l:llhs = len(a:lhs)
  let l:lrhs = len(a:rhs)
  if l:llhs ># l:lrhs
    return -1
  elseif l:llhs <# l:lrhs
    return 1
  endif
  if a:matches[a:lhs] ># a:matches[a:rhs]
    return -1
  elseif a:matches[a:lhs] <# a:matches[a:rhs]
    return 1
  endif
  return 0
endfunction

function! lsp#utils#_nearest_path(matches) abort
  return empty(a:matches) ?
              \ '' :
              \ sort(keys(a:matches), function('lsp#utils#_compare_nearest_path', [a:matches]))[0]
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

        return lsp#utils#_nearest_path(l:matched_paths)
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
   let l:str = substitute(a:str, '\$[0-9]\+\|\${\%(\\.\|[^}]\)\+}', '', 'g')
   let l:str = substitute(l:str, '\\\(.\)', '\1', 'g')
   let l:valid = matchstr(l:str, '^[^"'' (<{\[\t\r\n]\+')
   if empty(l:valid)
       return l:str
   endif
   if l:valid =~# ':$'
       return l:valid[:-2]
   endif
   return l:valid
endfunction

function! lsp#utils#_split_by_eol(text) abort
    return split(a:text, '\r\n\|\r\|\n', v:true)
endfunction

" parse command options like "-key" or "-key=value"
function! lsp#utils#parse_command_options(params) abort
    let l:result = {}
    for l:param in a:params
        let l:match = matchlist(l:param, '-\{1,2}\zs\([^=]*\)\(=\(.*\)\)\?\m')
        let l:result[l:match[1]] = l:match[3]
    endfor
    return l:result
endfunction

" polyfill for the neovim wait function
if exists('*wait')
    function! lsp#utils#_wait(timeout, condition, ...) abort
        if type(a:timeout) != type(0)
            return -3
        endif
        if type(get(a:000, 0, 0)) != type(0)
            return -3
        endif
        while 1
            let l:result=call('wait', extend([a:timeout, a:condition], a:000))
            if l:result != -3 " ignore spurious errors
                return l:result
            endif
        endwhile
    endfunction
else
    function! lsp#utils#_wait(timeout, condition, ...) abort
        try
            let l:timeout = a:timeout / 1000.0
            let l:interval = get(a:000, 0, 200)
            let l:Condition = a:condition
            if type(l:Condition) != type(function('eval'))
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
endif

function! lsp#utils#iteratable(list) abort
    return type(a:list) !=# v:t_list ? [] : a:list
endfunction
