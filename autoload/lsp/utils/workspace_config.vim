function! lsp#utils#workspace_config#get_value(server_name, item) abort
    try
        let l:server_info = lsp#get_server_info(a:server_name)
        let l:config = l:server_info['workspace_config']

        for l:section in split(a:item['section'], '\.')
            let l:config = l:config[l:section]
        endfor

        return l:config
    catch
        return v:null
    endtry
endfunction
