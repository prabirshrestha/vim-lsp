let s:use_vim_textprops = lsp#utils#_has_vim9textprops() && !has('nvim')

function! s:set_inlay_hints(data) abort
    let l:bufnr = bufnr('%')

    call s:clear_inlay_hints()

    if mode() !=# 'n' | return | endif

    if lsp#client#is_error(a:data['response']) | return | endif

    " Get hints from the response
    let l:hints = a:data['response']['result']
    if empty(l:hints)
        return
    endif

    for l:hint in l:hints
        let l:label = ''
        if type(l:hint.label) == v:t_list
            let l:label = join(map(copy(l:hint.label), {_,v -> v.value}), ' ')
        else
            let l:label = l:hint.label
        endif
        let l:text = (get(l:hint, 'paddingLeft', v:false) ? ' ' : '') . l:label . (get(l:hint, 'paddingRight', v:false) ? ' ' : '')
        if !has_key(l:hint, 'kind') || l:hint.kind ==# 1
            call prop_add(l:hint.position.line+1, l:hint.position.character+1, {'type': 'vim_lsp_inlay_hint_type', 'text': l:text, 'bufnr': l:bufnr})
        elseif l:hint.kind ==# 2
            call prop_add(l:hint.position.line+1, l:hint.position.character+1, {'type': 'vim_lsp_inlay_hint_parameter', 'text': l:text, 'bufnr': l:bufnr})
        endif
    endfor
endfunction

function! s:init_inlay_hints() abort
    if index(prop_type_list(), 'vim_lsp_inlay_hint') == -1
        call prop_type_add('vim_lsp_inlay_hint_type', { 'highlight': 'Label' })
        call prop_type_add('vim_lsp_inlay_hint_parameter', { 'highlight': 'Todo' })
    endif
endfunction

function! lsp#internal#inlay_hints#_disable() abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:clear_inlay_hints() abort
    let l:bufnr = bufnr('%')
    for l:prop in prop_list(1, {'end_lnum': line('$'), 'types': ['vim_lsp_inlay_hint_type'], 'bufnr': l:bufnr})
        call prop_remove({'id': l:prop.id})
    endfor
    for l:prop in prop_list(1, {'end_lnum': line('$'), 'types': ['vim_lsp_inlay_hint_parameter'], 'bufnr': l:bufnr})
        call prop_remove({'id': l:prop.id})
    endfor
endfunction

function! s:send_inlay_hints_request() abort
    let l:capability = 'lsp#capabilities#has_inlay_hint_provider(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if empty(l:servers)
        return lsp#callbag#empty()
    endif

    return lsp#request(l:servers[0], {
        \ 'method': 'textDocument/inlayHint',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': line('$')-1, 'character': len(getline(line('$')))}}
        \  },
        \ })
endfunction

function! lsp#internal#inlay_hints#_enable() abort
    if !s:use_vim_textprops | return | endif
    if !g:lsp_inlay_hints_enabled | return | endif

    call s:init_inlay_hints()
    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#fromEvent(['CursorMoved', 'CursorHold']),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent(['InsertEnter', 'BufLeave']),
        \       lsp#callbag#tap({_ -> s:clear_inlay_hints() }),
        \   )
        \ ),
        \ lsp#callbag#filter({_ -> g:lsp_inlay_hints_enabled }),
        \ lsp#callbag#debounceTime(g:lsp_inlay_hints_delay),
        \ lsp#callbag#filter({_->getbufvar(bufnr('%'), '&buftype') !~# '^(help\|terminal\|prompt\|popup)$'}),
        \ lsp#callbag#switchMap({_->
        \   lsp#callbag#pipe(
        \       s:send_inlay_hints_request(),
        \       lsp#callbag#materialize(),
        \       lsp#callbag#filter({x->lsp#callbag#isNextNotification(x)}),
        \       lsp#callbag#map({x->x['value']})
        \   )
        \ }),
        \ lsp#callbag#subscribe({x->s:set_inlay_hints(x)}),
        \)
endfunction
