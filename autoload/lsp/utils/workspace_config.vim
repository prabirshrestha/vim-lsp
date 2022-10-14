function! lsp#utils#workspace_config#get(server_name) abort
    try
        let l:server_info = lsp#get_server_info(a:server_name)
        let l:config_type = type(l:server_info['workspace_config'])

        if l:config_type == v:t_func
          let l:config = l:server_info['workspace_config'](l:server_info)
        else
          let l:config = l:server_info['workspace_config']
        endif

        return l:config
    catch
        return v:null
    endtry
endfunction

function! lsp#utils#workspace_config#projection(config, item) abort
    try
        let l:config = a:config

        for l:section in split(a:item['section'], '\.')
            let l:config = l:config[l:section]
        endfor

        return l:config
    catch
        return v:null
    endtry
endfunction

function! lsp#utils#workspace_config#get_value(server_name, item) abort
    let l:config = lsp#utils#workspace_config#get(a:server_name)
    return lsp#utils#workspace_config#projection(l:config, a:item)
endfunction
