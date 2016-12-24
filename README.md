vim-lsp (experimental)
======================

Async [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) plugin for vim8 and neovim.
Internally vim-lsp uses [async.vim](https://github.com/prabirshrestha/async.vim).

Language Server Protocol VIM Client usage
=========================================

Sample usage talking with `langserver-go`

```vim
function! s:on_stderr(id, data, event)
    echom 'lsp('.a:id.'):stderr:'.join(a:data, "\r\n")
endfunction

function! s:on_exit(id, status, event)
    echom 'lsp('.a:id.'):exit:'.a:status
endfunction

function! s:on_notification(id, data, event)
    if lsp#lspClient#is_error(a:data.response)
        echom 'lsp('.a:id.'):notification:notification error receieved for '.a:data.request.method
    elseif lsp#lspClient#is_server_instantiated_notification(a:data)
        " request key will not be present in a:data
        " make sure to check before accessing a:data.request in order to prevent unhandled errors
        echom 'lsp('.a:id.'):notification:notification success receieved for '.json_encode(a:data.response)
    else
        echom 'lsp('.a:id.'):notification:notification success receieved for '.a:data.request.method
    endif
endfunction

function! s:on_notification1(id, data, event)
    echom 'lsp('.a:id.'):notification1:'json_encode(a:data)
endfunction

" go get github.com/sourcegraph/go-langserver/langserver/cmd/langserver-go
let g:lsp_id = lsp#lspClient#start({
    \ 'cmd': ['langserver-go', '-trace', '-logfile', expand('~/Desktop/langserver-go.log')],
    \ 'on_stderr': function('s:on_stderr'),
    \ 'on_exit': function('s:on_exit'),
    \ 'on_notification': function('s:on_notification')
\ })

if g:lsp_id > 0
    echom 'lsp server running'
    call lsp#lspClient#send(g:lsp_id, {
        \ 'method': 'initialize',
        \ 'params': {
            \ 'capabilities': {},
            \ 'rootPath': 'file:///D:/go/src/github.com/nsf/gocode'
        \ },
        \ 'on_notification': function('s:on_notification1')
   \ })
else
    echom 'failed to start lsp server'
endif

" call lsp#lspClient#stop(g:lsp_id)
```
