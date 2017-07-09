function! lsp#ui#fzf#get_symbols() abort
    let l:servers = lsp#get_whitelisted_servers()
    for l:server in l:servers
        call lsp#utils#step#start([
            \ {s->s.callback()}
            \ ])
    endfor
endfunction
