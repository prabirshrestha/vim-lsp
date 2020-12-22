" options - {
"   bufnr: bufnr('%')       " required
"   server - 'server_name'  " optional
"   sync: 0                 " optional, async by default
" }
function! lsp#internal#document_format#format(options) abort
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_formatting_provider(v:val)')
    endif

    if len(l:servers) == 0
        let l:filetype = getbufvar(a:options['bufnr'], '&filetype')
        call lsp#utils#error('DocumentFormat not supported for ' . l:filetype)
        return
    endif

    " TODO: ask user to select server for formatting if there are multiple servers
    let l:server = l:servers[0]

    call lsp#stream(1, { 'command': 'LspDocumentFormat' })
    let l:command_id = lsp#_new_command() " TODO remove when everything moved to stream

    let l:request = {
        \ 'method': 'textDocument/formatting',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(a:options['bufnr']),
        \   'options': {
        \       'tabSize': getbufvar(a:options['bufnr'], '&tabstop'),
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
                \ ).wait({ 'sleep': get(a:options, 'sleep', 1), 'timeout': get(a:options, 'timeout', -1) })
            call s:format_next(l:x[0])
            call s:format_complete()
        catch
            call s:format_error([v:exception, v:throwpoint])
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
    call lsp#log('DocumentFormat failed', a:e)
    call lsp#utils#error('DocumentFormat failed')
endfunction

function! s:format_complete() abort
    redraw | echo 'DocumentFormat complete'
endfunction
