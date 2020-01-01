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

    normal! V
    call setpos("'<", [l:bufnr, l:start_line, l:start_col])
    call setpos("'>", [l:bufnr, l:end_line, l:end_col])
endfunction
