function! lsp#test#projectdir(name) abort
    if a:name ==# 'rust'
        return expand('%:p:h') .'/test/testproject-rust'
    elseif a:name ==# 'go'
        return expand('%:p:h') .'/test/testproject-go'
    else
        throw 'projectdir not supported for ' . a:name
    endif
endfunction

function! lsp#test#openproject(name, options) abort
    if a:name ==# 'go'
        filetype on

        call lsp#register_server({
            \ 'name': 'gopls',
            \ 'cmd': ['gopls'],
            \ 'allowlist': ['go'],
            \ })

        call lsp#enable()

        " open .go file to trigger gopls then close it
        execute printf('keepalt keepjumps edit %s', lsp#test#projectdir(a:name) . '/documentformat.go')
        " wait for server starting
        call lsp#test#wait(10000, {-> lsp#get_server_status('gopls') ==# 'running' })

        %bwipeout!
    else
        throw 'open project not not supported for ' . a:name
    endif
endfunction

function! lsp#test#closeproject(name) abort
    if lsp#test#hasproject(a:name)
        silent! call lsp#stop_sserver(a:name)
    endif
endfunction

function! lsp#test#hasproject(name) abort
    if a:name ==# 'go' && executable('gopls')
        return 1
    else
        return 0
    endif
endfunction

function! lsp#test#wait(timeout, condition) abort
    call lsp#utils#_wait(a:timeout, a:condition)
endfunction
