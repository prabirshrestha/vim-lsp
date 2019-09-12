let s:last_help = {
            \   'line': -1,
            \   'trigger_text': '',
            \ }

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

        let l:options = { 'statusline': ' LSP SignatureHelp' }
        if index(['i', 'ic', 'ix'], mode()) >= 0
            let l:options['closing_hooks'] = ['InsertLeave']
            let l:options['disable_double_tap'] = v:true
        endif
        call lsp#ui#vim#output#preview(a:server, l:contents, l:options)
        return
    else
        " signature help is used while inserting. So this must be graceful.
        "call lsp#utils#error('No signature help information found')
    endif
endfunction

function! s:get_parameter_label(signature, parameter) abort
    if has_key(a:parameter, 'label')
        if type(a:parameter['label']) == v:t_list
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

    if type(a:parameter['documentation']) == v:t_dict
        let l:doc = copy(a:parameter['documentation'])
        let l:doc['value'] = printf('***%s*** - %s', a:parameter['label'], l:doc['value'])
        return l:doc
    endif
    return printf('***%s*** - %s', a:parameter['label'], l:doc)
endfunction

function! s:trigger_if_need() abort
    let l:server_names = filter(lsp#get_whitelisted_servers(), 'lsp#capabilities#has_signature_help_provider(v:val)')
    if len(l:server_names) == 0
        return
    endif

    let l:line = line('.')

    " To support wrapping function arguments.
    let l:text = ''
    if l:line > 2 | let l:text .= getline(l:line - 2) . "\n" | endif
    if l:line > 1 | let l:text .= getline(l:line  - 1) . "\n" | endif
    let l:text .= getline(l:line)[0 : col('.') - 2]

    for l:server_name in l:server_names
        let l:special_chars = [')']
        let l:trigger_chars = lsp#capabilities#get_signature_help_trigger_characters(l:server_name)

        " Remove until the last trigger character.
        let l:trigger_text = s:remove_until_chars(l:text, l:special_chars + l:trigger_chars)

        let l:char = strgetchar(l:trigger_text, strchars(l:trigger_text) - 1)
        if l:char != -1
            if index(l:trigger_chars, nr2char(l:char)) >= 0
                if s:last_help['line'] != l:line || s:last_help['trigger_text'] !=# l:trigger_text
                    call lsp#ui#vim#signature_help#get_signature_help_under_cursor()
                    let s:last_help['line'] = l:line
                    let s:last_help['trigger_text'] = l:trigger_text
                endif
            else
                call lsp#ui#vim#output#closepreview()
            endif
        endif
    endfor
endfunction

function! s:remove_until_chars(text, chars) abort
    let l:text_len = strchars(a:text)
    let l:i = -1
    while v:true
        let l:nr = strgetchar(a:text, l:text_len + l:i)
        if l:nr == -1 || index(a:chars, nr2char(l:nr)) >= 0
            break
        endif
        let l:i -= 1
    endwhile
   return strcharpart(a:text, 0, l:text_len + l:i + 1)
endfunction

function! lsp#ui#vim#signature_help#setup() abort
    augroup _lsp_signature_help_
        autocmd!
        autocmd TextChangedI * call s:trigger_if_need()
        autocmd TextChangedP * call s:trigger_if_need()
        autocmd InsertEnter * let s:last_help = { 'line': -1, 'trigger_text': '' }
        autocmd InsertLeave * let s:last_help = { 'line': -1, 'trigger_text': '' }
    augroup END
endfunction

