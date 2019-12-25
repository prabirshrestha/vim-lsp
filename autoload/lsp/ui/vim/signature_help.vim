function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
endfunction

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
        " Get current signature.
        let l:signatures = get(a:data['response']['result'], 'signatures', [])
        let l:signature_index = get(a:data['response']['result'], 'activeSignature', 0)
        let l:signature = get(l:signatures, l:signature_index, {})
        if empty(l:signature)
            return
        endif

        " Signature label.
        let l:label = l:signature['label']

        " Mark current parameter.
        if has_key(a:data['response']['result'], 'activeParameter')
            let l:parameters = get(l:signature, 'parameters', [])
            let l:parameter_index = a:data['response']['result']['activeParameter']
            let l:parameter = get(l:parameters, l:parameter_index, {})
            let l:parameter_label = s:get_parameter_label(l:signature, l:parameter)
            if !empty(l:parameter_label)
                let l:label = substitute(l:label, '\V\(' . escape(l:parameter_label, '\/?') . '\)', '`\1`', 'g')
            endif
        endif

        let l:contents = [l:label]

        if exists('l:parameter')
            let l:parameter_doc = s:get_parameter_doc(l:parameter)
            if !empty(l:parameter_doc)
                call add(l:contents, '')
                call add(l:contents, l:parameter_doc)
                call add(l:contents, '')
            endif
        endif

        if has_key(l:signature, 'documentation')
            call add(l:contents, l:signature['documentation'])
        endif

        call lsp#ui#vim#output#preview(a:server, l:contents, {'statusline': ' LSP SignatureHelp'})
        return
    else
        " signature help is used while inserting. So this must be graceful.
        "call lsp#utils#error('No signature help information found')
    endif
endfunction

function! s:get_parameter_label(signature, parameter) abort
    if has_key(a:parameter, 'label')
        if type(a:parameter['label']) == type([])
            let l:string_range = a:parameter['label']
            return strcharpart(
                        \ a:signature['label'],
                        \ l:string_range[0],
                        \ l:string_range[1] - l:string_range[0])
        endif
        return a:parameter['label']
    endif
    return ''
endfunction

function! s:get_parameter_doc(parameter) abort
    if !has_key(a:parameter, 'documentation')
        return ''
    endif

    let l:doc = copy(a:parameter['documentation'])
    if type(l:doc) == type({})
        let l:doc['value'] = printf('***%s*** - %s', a:parameter['label'], l:doc['value'])
        return l:doc
    endif
    return printf('***%s*** - %s', a:parameter['label'], l:doc)
endfunction

function! s:insert_char_pre() abort
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
    augroup END
endfunction
