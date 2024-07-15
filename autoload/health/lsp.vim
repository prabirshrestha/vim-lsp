function! s:BuildConfigBlock(section, info) abort
    let l:block = get(a:info, a:section, '')
    if !empty(l:block)
        return printf("### %s\n%s\n", a:section, l:block)
    endif
    return ''
endf


function! health#lsp#check() abort
    call v:lua.vim.health.start('server status')
    let l:server_status = lsp#collect_server_status()

    let l:has_printed = v:false
    for l:k in sort(keys(l:server_status))
        let l:report = l:server_status[l:k]

        let l:status_msg = printf('%s: %s', l:k, l:report.status)
        if l:report.status == 'running'
            call v:lua.vim.health.ok(l:status_msg)
        elseif l:report.status == 'failed'
            call v:lua.vim.health.error(l:status_msg, 'See :help g:lsp_log_verbose to debug server failure.')
        else
            call v:lua.vim.health.warn(l:status_msg)
        endif
        let l:has_printed = v:true
    endfor

    if !l:has_printed
        call v:lua.vim.health.warn('no servers connected')
    endif

    for l:k in sort(keys(l:server_status))
        call v:lua.vim.health.start(printf('server configuration: %s', l:k))
        let l:report = l:server_status[l:k]

        let l:msg = "\t\n"
        let l:msg .= s:BuildConfigBlock('allowlist', l:report.info)
        let l:msg .= s:BuildConfigBlock('blocklist', l:report.info)
        let l:cfg = get(l:report.info, 'workspace_config', '')
        if !empty(l:cfg)
            if get(g:, 'loaded_scriptease', 0)
                let l:cfg = scriptease#dump(l:cfg, {'width': &columns-1})
            else
                let l:cfg = json_encode(l:cfg)
                " Add some whitespace to make it readable.
                let l:cfg = substitute(l:cfg, '[,{(\[]', "&\n\t", 'g')
                let l:cfg = substitute(l:cfg, '":', '& ', 'g')
                let l:cfg = substitute(l:cfg, '\v[})\]]+', "\n&", 'g')
                let l:cfg = substitute(l:cfg, '\n\s*\n', "\n", 'g')
            endif
            let l:msg .= printf("### workspace_config\n```json\n%s\n```", l:cfg)
        endif
        call v:lua.vim.health.info(l:msg)
    endfor

    call v:lua.vim.health.start('Performance')
    if lsp#utils#has_lua() && g:lsp_use_lua
        call v:lua.vim.health.ok('Using lua for faster performance.')
    else
        call v:lua.vim.health.warn('Missing requirements to enable lua for faster performance.')
    endif

endf

