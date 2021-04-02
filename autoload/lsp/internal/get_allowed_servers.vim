function! lsp#internal#get_allowed_servers#get(buffer_filetype, servers, servers_update_counter, active_servers) abort
    if has_key(a:active_servers, a:buffer_filetype)
      let l:cached_servers = a:active_servers[a:buffer_filetype]
      if get(l:cached_servers, 'update_cnt', -1) == a:servers_update_counter
        " copy the list to prevent inplace changes
        return copy(l:cached_servers['servers'])
      endif
    endif

    if g:lsp_use_lua && lsp#utils#has_lua()
      let l:active_servers = empty(a:servers) ? [] : luaeval(
            \ 'require("lsp").get_allowed_servers(_A.buffer_filetype, _A.servers)',
            \ {'buffer_filetype': a:buffer_filetype, 'servers': a:servers}
            \ )

    else
      let l:active_servers = s:get_allowed_servers_vim(a:buffer_filetype, a:servers)
    endif

    " Only update cache when needed
    if ! has_key(a:active_servers, a:buffer_filetype)
          \ || get(a:active_servers[a:buffer_filetype], 'update_cnt', -1) < a:servers_update_counter
      let a:active_servers[a:buffer_filetype] = {
            \ 'update_cnt': a:servers_update_counter,
            \ 'servers': copy(l:active_servers),
            \ }
    endif

    return l:active_servers
endfunction


function! s:get_allowed_servers_vim(buffer_filetype, servers) abort
    let l:active_servers = []
    for l:server_name in keys(a:servers)
        let l:server_info = a:servers[l:server_name]['server_info']
        let l:blocked = 0

        let l:blocklist = get(l:server_info, 'blocklist', get(l:server_info, 'blacklist', []))
        if index(l:blocklist, '*') >= 0 || index(l:blocklist, a:buffer_filetype, 0, 1) >= 0
          continue
        endif

        let l:allowlist = get(l:server_info, 'allowlist', get(l:server_info, 'whitelist', []))
        if index(l:allowlist, '*') >= 0 || index(l:allowlist, a:buffer_filetype, 0, 1) >= 0
          let l:active_servers += [l:server_name]
        endif
    endfor
    return l:active_servers
endfunction
