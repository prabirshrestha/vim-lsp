function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
endfunction

let s:last_help = {}

function! lsp#ui#vim#signature_help#get_signature_help_under_cursor() abort
    let l:servers = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_signature_help_provider(v:val)')

    if len(l:servers) == 0
        call s:not_supported('Retrieving signature help')
        return
    endif

    let l:position = lsp#get_position()
    let l:position.character += 1
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'method': 'textDocument/signatureHelp',
            \ 'params': {
            \   'textDocument': lsp#get_text_document_identifier(),
            \   'position': position,
            \ },
            \ 'on_notification': function('s:handle_signature_help', [l:server]),
            \ })
    endfor

    echo 'Retrieving signature help ...'
    return
endfunction

function! s:handle_signature_help(server, data) abort
    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve signature help information for ' . a:server)
        return
    endif

    if !has_key(a:data['response'], 'result')
        return
    endif

    if !empty(a:data['response']['result']) && !empty(a:data['response']['result']['signatures'])
        let l:signature = a:data['response']['result']['signatures'][0]
        let l:contents = [l:signature['label']]
        if has_key(l:signature, 'documentation')
            call add(l:contents, l:signature['documentation'])
        endif
        let s:last_help = {'server': a:server, 'contents': l:contents}
        call s:display_signature_help()
        return
    else
        " signature help is used while inserting. So this must be graceful.
        "call lsp#utils#error('No signature help information found')
    endif
endfunction

function! s:display_signature_help() abort
    if !has_key(s:last_help, 'server') || !has_key(s:last_help, 'contents') | return | endif
    call lsp#ui#vim#output#preview(s:last_help['server'], s:last_help['contents'], {'statusline': ' LSP SignatureHelp'})
endfunction

function! s:insert_char_pre() abort
    " When typing ')', reset signature help.
    if v:char ==# ')'
        let s:last_help = {}
    endif

    call timer_start(0, {_ -> s:display_signature_help() })

    let l:buf = bufnr('%')
    for l:server_name in lsp#get_whitelisted_servers(l:buf)
        let l:keys = lsp#capabilities#get_signature_help_trigger_characters(l:server_name)
        for l:key in l:keys
            if l:key ==# v:char
                call timer_start(0, {_-> lsp#ui#vim#signature_help#get_signature_help_under_cursor() })
            endif
        endfor
    endfor
endfunction

function! lsp#ui#vim#signature_help#setup() abort
    augroup _lsp_signature_help_
        autocmd!
        autocmd InsertCharPre <buffer> call s:insert_char_pre()
        autocmd InsertLeave let s:last_help = {}
    augroup END
endfunction
