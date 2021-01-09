" https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol
" options - {
"   bufnr: bufnr('%')       " optional
"   server - 'server_name'  " optional
"   query: ''               " optional
" }
function! lsp#internal#workspace_symbol#search#do(options) abort
    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_document_symbol_provider(v:val)')
    endif

    if len(l:servers) == 0
        echom 'textDocument/workspaceSymbol not supported'
        call lsp#utils#error('textDocument/workspaceSymbol not supported')
        return
    endif

    redraw | echo 'Retrieving workspace symbols ...'

    call lsp#internal#ui#quickpick#open({
        \ 'items': [],
        \ 'busy': 1,
        \ 'input': get(a:options, 'query', ''),
        \ 'key': 'text',
        \ 'on_change': function('s:on_change'),
        \ 'on_accept': function('s:on_accept'),
        \ 'on_close': function('s:on_close'),
        \ })
endfunction

function! s:on_change(...) abort
endfunction

function! s:on_accept(...) abort
endfunction

function! s:on_close(...) abort
endfunction
