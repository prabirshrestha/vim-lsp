" options - {
"   bufnr: bufnr('%')       " required
"   type: ''                " optional: defaults to visualmode(). overridden by opfunc
"   server - 'server_name'  " optional
"   sync: 0                 " optional, defaults to 0 (async)
" }
function! lsp#internal#document_range_formatting#format(options) abort
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_range_formatting_provider(v:val)')
    endif

    if len(l:servers) == 0
        let l:filetype = getbufvar(a:options['bufnr'], '&filetype')
        call lsp#utils#error('textDocument/rangeFormatting not supported for ' . l:filetype)
        return
    endif

    " TODO: ask user to select server for formatting if there are multiple servers
    let l:server = l:servers[0]

    redraw | echo 'Formatting Document Range ...'

    call lsp#_new_command()

    let [l:start_lnum, l:start_col, l:end_lnum, l:end_col] = s:get_selection_pos(get(a:options, 'type', visualmode()))
    let l:start_char = lsp#utils#to_char('%', l:start_lnum, l:start_col)
    let l:end_char = lsp#utils#to_char('%', l:end_lnum, l:end_col)

    let l:request = {
        \ 'method': 'textDocument/rangeFormatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(a:options['bufnr']),
        \   'range': {
        \       'start': { 'line': l:start_lnum - 1, 'character': l:start_char },
        \       'end': { 'line': l:end_lnum - 1, 'character': l:end_char },
        \   },
        \   'options': {
        \       'tabSize': lsp#utils#buffer#get_indent_size(a:options['bufnr']),
        \       'insertSpaces': getbufvar(a:options['bufnr'], '&expandtab') ? v:true : v:false,
        \   }
        \ },
        \ 'bufnr': a:options['bufnr'],
        \ }

    if get(a:options, 'sync', 0) == 1
        try
            let l:x = lsp#callbag#pipe(
                \ lsp#request(l:server, l:request),
                \ lsp#callbag#takeUntil(lsp#callbag#pipe(
                \   lsp#stream(),
                \   lsp#callbag#filter({x->has_key(x, 'command')}),
                \ )),
                \ lsp#callbag#toList(),
                \ ).wait({ 'sleep': get(a:options, 'sleep', 1), 'timeout': get(a:options, 'timeout', g:lsp_format_sync_timeout) })
            call s:format_next(l:x[0])
            call s:format_complete()
        catch
            call s:format_error(v:exception . ' ' . v:throwpoint)
        endtry
    else
        return lsp#callbag#pipe(
            \ lsp#request(l:server, l:request),
            \ lsp#callbag#takeUntil(lsp#callbag#pipe(
            \   lsp#stream(),
            \   lsp#callbag#filter({x->has_key(x, 'command')}),
            \ )),
            \ lsp#callbag#subscribe({
            \   'next':{x->s:format_next(x)},
            \   'error': {x->s:format_error(e)},
            \   'complete': {->s:format_complete()},
            \ }),
            \ )
    endif
endfunction

function! s:format_next(x) abort
    call lsp#utils#text_edit#apply_text_edits(a:x['request']['params']['textDocument']['uri'], a:x['response']['result'])
endfunction

function! s:format_error(e) abort
    call lsp#log('Formatting Document Range Failed', a:e)
    call lsp#utils#error('Formatting Document Range Failed.' . (type(a:e) == type('') ? a:e : ''))
endfunction

function! s:format_complete() abort
    redraw | echo 'Formatting Document Range complete'
endfunction

function! s:get_selection_pos(type) abort
    " TODO: support bufnr
    if a:type ==? 'v'
        let l:start_pos = getpos("'<")[1:2]
        let l:end_pos = getpos("'>")[1:2]
        " fix end_pos column (see :h getpos() and :h 'selection')
        let l:end_line = getline(l:end_pos[0])
        let l:offset = (&selection ==# 'inclusive' ? 1 : 2)
        let l:end_pos[1] = len(l:end_line[:l:end_pos[1]-l:offset])
        " edge case: single character selected with selection=exclusive
        if l:start_pos[0] == l:end_pos[0] && l:start_pos[1] > l:end_pos[1]
            let l:end_pos[1] = l:start_pos[1]
        endif
    elseif a:type ==? 'line'
        let l:start_pos = [line("'["), 1]
        let l:end_lnum = line("']")
        let l:end_pos = [line("']"), len(getline(l:end_lnum))]
    elseif a:type ==? 'char'
        let l:start_pos = getpos("'[")[1:2]
        let l:end_pos = getpos("']")[1:2]
    else
        let l:start_pos = [0, 0]
        let l:end_pos = [0, 0]
    endif

    return l:start_pos + l:end_pos
endfunction

function! lsp#internal#document_range_formatting#opfunc(type) abort
    call lsp#internal#document_range_formatting#format({
                \ 'type': a:type,
                \ 'bufnr': bufnr('%'),
                \ })
endfunction
