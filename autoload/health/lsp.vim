function! s:BuildConfigBlock(section, info) abort
    let l:block = get(a:info, a:section, '')
    if !empty(l:block)
        return printf("### %s\n%s\n", a:section, l:block)
    endif
    return ''
endf


function! health#lsp#check() abort
    call s:report_start('server status')
    let l:server_status = lsp#collect_server_status()

    let l:has_printed = v:false
    for l:k in sort(keys(l:server_status))
        let l:report = l:server_status[l:k]

        let l:status_msg = printf('%s: %s', l:k, l:report.status)
        if l:report.status == 'running'
            call s:report_ok(l:status_msg)
        elseif l:report.status == 'failed'
            call health#report_error(l:status_msg, 'See :help g:lsp_log_verbose to debug server failure.')
        else
            call s:report_warn(l:status_msg)
        endif
        let l:has_printed = v:true
    endfor

    if !l:has_printed
        call s:report_warn('no servers connected')
    endif

    for l:k in sort(keys(l:server_status))
        call s:report_start(printf('server configuration: %s', l:k))
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
        call health#report_info(l:msg)
    endfor

    call s:report_start('Performance')
    if lsp#utils#has_lua() && g:lsp_use_lua
        call s:report_ok('Using lua for faster performance.')
    else
        call s:report_warn('Missing requirements to enable lua for faster performance.')
    endif

endf

function! s:report_start(report) abort
  if has('nvim-0.10')
    call v:lua.vim.health.start(a:report)
  else
    call health#report_start(a:report)
  endif
endf

function! s:report_warn(report) abort
  if has('nvim-0.10')
    call v:lua.vim.health.warn(a:report)
  else
    call health#report_warn(a:report)
  endif
endf

function! s:report_ok(report) abort
  if has('nvim-0.10')
    call v:lua.vim.health.ok(a:report)
  else
    call health#report_ok(a:report)
  endif
endf
