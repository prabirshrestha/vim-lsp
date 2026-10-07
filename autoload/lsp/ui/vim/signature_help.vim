" vint: -ProhibitUnusedVariable
let s:debounce_timer_id = 0

" Keeps track of the last signature help invoked per server
let s:last_signature_help = {}

function! s:not_supported(what) abort
    return lsp#utils#error(a:what.' not supported for '.&filetype)
endfunction

function! lsp#ui#vim#signature_help#get_signature_help_under_cursor() abort
    let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_signature_help_provider(v:val)')

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
            \   'position': l:position,
            \ },
            \ 'on_notification': function('s:handle_signature_help', [l:server]),
            \ })
    endfor

    call lsp#log('Retrieving signature help')
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
        " Compare the newly received signatures against the cached (if any)
        let l:old_entry = get(s:last_signature_help, a:server, {})
        let l:old_result = get(l:old_entry, 'result', {})
        let l:old_position = get(l:old_entry, 'position', {})
        let l:old_signatures = get(l:old_result, 'signatures', [])
        let l:new_position = a:data['request']['params']['position']
        let l:new_signatures = a:data['response']['result']['signatures']

        let l:is_same_line = has_key(l:old_position, 'line') && has_key(l:new_position, 'line')
            \ && l:old_position['line'] ==# l:new_position['line']
        let l:is_same_call = l:is_same_line && l:old_signatures ==# l:new_signatures

        " If this is still the same signature, try to advance to the next
        " overload by incrementing the previously active signature index.
        if l:is_same_call
            let l:next_signature_index = get(l:old_result, 'activeSignature', 0) + 1
            if l:next_signature_index < len(l:new_signatures)
                let a:data['response']['result']['activeSignature'] = l:next_signature_index
            else
                let a:data['response']['result']['activeSignature'] = 0
            endif
        endif

        " Cache the last signature
        let s:last_signature_help[a:server] = {
            \ 'result': a:data['response']['result'],
            \ 'position': l:new_position,
            \ }

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

function! s:on_cursor_moved() abort
    let l:bufnr = bufnr('%')
    call timer_stop(s:debounce_timer_id)
    if g:lsp_signature_help_enabled
        let s:debounce_timer_id = timer_start(g:lsp_signature_help_delay, function('s:on_text_changed_after', [l:bufnr]), { 'repeat': 1 })
    endif
endfunction

function! s:on_text_changed_after(bufnr, timer) abort
    if bufnr('%') != a:bufnr
        return
    endif
    if index(['i', 's'], mode()[0]) == -1
        return
    endif
    if win_id2win(lsp#ui#vim#output#getpreviewwinid()) >= 1
        return
    endif

    " Cache trigger chars since this loop is heavy
    let l:chars = get(b:, 'lsp_signature_help_trigger_character', [])
    if empty(l:chars)
        for l:server_name in lsp#get_allowed_servers(a:bufnr)
            let l:chars += lsp#capabilities#get_signature_help_trigger_characters(l:server_name)
        endfor
        let b:lsp_signature_help_trigger_character = l:chars
    endif

    if index(l:chars, lsp#utils#_get_before_char_skip_white()) >= 0
        call lsp#ui#vim#signature_help#get_signature_help_under_cursor()
    endif
endfunction

function! lsp#ui#vim#signature_help#setup() abort
    augroup _lsp_signature_help_
        autocmd!
        autocmd CursorMoved,CursorMovedI * call s:on_cursor_moved()
    augroup END
endfunction

function! lsp#ui#vim#signature_help#_disable() abort
    augroup _lsp_signature_help_
        autocmd!
    augroup END
endfunction

