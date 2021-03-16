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
    if a:name ==# 'rust'
        call lsp#enable()
        call lsp#register_server({
            \ 'name': 'rust',
            \ 'cmd': ['rust-analyzer'],
            \ 'allowlist': ['rust'],
            \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'Cargo.toml'))},
            \ 'capabilities': { 'experimental': { 'statusNotification': v:true } },
            \ })
        " status notification required to know ready status of rust analyzer
        " for more info refer to: https://github.com/rust-analyzer/rust-analyzer/pull/5188

        " open .rs file to trigger rust analyzer then close it
        execute printf('keepalt keepjumps edit %s', lsp#test#projectdir(a:name) . '/src/documentformat.rs')
        %bwipeout!

        " wait for ready status from rust-analyzer
        call lsp#callbag#pipe(
            \ lsp#stream(),
            \ lsp#callbag#filter({x->has_key(x, 'response') && has_key(x['response'], 'method')
            \   && x['response']['method'] ==# 'rust-analyzer/status' && x['response']['params']['status'] ==# 'ready' }),
            \ lsp#callbag#take(1),
            \ lsp#callbag#toList(),
            \ ).wait({ 'timeout': 10000, 'sleep': 100 })
    elseif a:name ==# 'go'
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
    if a:name ==# 'rust' && executable('rust-analyzer')
        return 1
    elseif a:name ==# 'go' && executable('gopls')
        return 1
    else
        return 0
    endif
endfunction

function! lsp#test#wait(timeout, condition) abort
    call lsp#utils#_wait(a:timeout, a:condition)
endfunction
