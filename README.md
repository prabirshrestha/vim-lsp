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
    echom 'lsp('.a:id.'):notification:notification receieved'
endfunction

function! s:on_notification1(id, data, event)
    echom 'lsp('.a:id.'):notification1:'json_encode(a:data)
endfunction

" go get github.com/sourcegraph/go-langserver/langserver/cmd/langserver-go
let s:lsp_id = lsp#lspClient#start({
    \ 'cmd': ['langserver-go', '-trace', '-logfile', expand('~/Desktop/langserver-go.log')],
    \ 'on_stderr': function('s:on_stderr'),
    \ 'on_exit': function('s:on_exit'),
    \ 'on_notification': function('s:on_notification')
\ })

if s:lsp_id > 0
    echom 'lsp server running'
    call lsp#lspClient#send(s:lsp_id, {
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
```
