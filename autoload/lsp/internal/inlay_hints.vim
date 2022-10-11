let s:use_vim_textprops = lsp#utils#_has_vim_virtual_text() && !has('nvim')

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

    let l:not_curline = s:has_inlay_hints_mode('!curline')
    for l:hint in l:hints
        if l:not_curline && l:hint.position.line+1 ==# line('.')
            continue
        endif
        let l:label = ''
        if type(l:hint.label) ==# v:t_list
            let l:label = join(map(copy(l:hint.label), {_,v -> v.value}), ', ')
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
    if index(prop_type_list(), 'vim_lsp_inlay_hint_type') ==# -1
        call prop_type_add('vim_lsp_inlay_hint_type', { 'highlight': 'lspInlayHintsType' })
        call prop_type_add('vim_lsp_inlay_hint_parameter', { 'highlight': 'lspInlayHintsParameter' })
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
    call prop_remove({'type': 'vim_lsp_inlay_hint_type', 'bufnr': l:bufnr, 'all': v:true})
    call prop_remove({'type': 'vim_lsp_inlay_hint_parameter', 'bufnr': l:bufnr, 'all': v:true})
endfunction

function! s:has_inlay_hints_mode(value) abort
    let l:m = get(g:, 'lsp_inlay_hints_mode', {})
    if type(l:m) != v:t_dict | return v:false | endif
    if mode() ==# 'i'
        let l:a = get(l:m, 'insert', [])
    elseif mode() ==# 'n'
        let l:a = get(l:m, 'normal', [])
    else
        return v:false
    endif
    if type(l:a) != v:t_list | return v:false | endif
    return index(l:a, a:value) != -1 ? v:true : v:false
endfunction

function! s:send_inlay_hints_request() abort
    let l:capability = 'lsp#capabilities#has_inlay_hint_provider(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if empty(l:servers)
        return lsp#callbag#empty()
    endif

    if s:has_inlay_hints_mode('curline')
        let l:range = lsp#utils#range#get_range_curline()
    else
        let l:range = lsp#utils#range#get_range()
    endif
    return lsp#request(l:servers[0], {
        \ 'method': 'textDocument/inlayHint',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'range': l:range,
        \  },
        \ })
endfunction

function! lsp#internal#inlay_hints#_enable() abort
    if !s:use_vim_textprops | return | endif
    if !g:lsp_inlay_hints_enabled | return | endif

    if !hlexists('lspInlayHintsType')
        highlight link lspInlayHintsType Label
    endif
    if !hlexists('lspInlayHintsParameter')
        highlight link lspInlayHintsParameter Todo
    endif

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
