let s:use_vim_textprops = has('textprop') && !has('nvim')
let s:prop_id = 11

function! lsp#internal#highlight_references#_enable() abort
    " don't event bother registering if the feature is disabled
    if !g:lsp_highlight_references_enabled | return | endif

    " Highlight group for references
    if !hlexists('lspReference')
        highlight link lspReference CursorColumn
    endif

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#fromEvent(['CursorMoved', 'CursorHold']),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent('InsertEnter'),
        \       lsp#callbag#tap({_ -> s:clear_highlights() }),
        \   )
        \ ),
        \ lsp#callbag#filter({_ -> g:lsp_highlight_references_enabled }),
        \ lsp#callbag#debounceTime(g:lsp_highlight_references_delay),
        \ lsp#callbag#map({_->{'bufnr': bufnr('%'), 'curpos': getcurpos()[0:2], 'changedtick': b:changedtick }}),
        \ lsp#callbag#distinctUntilChanged({a,b -> a['bufnr'] == b['bufnr'] && a['curpos'] == b['curpos'] && a['changedtick'] == b['changedtick']}),
        \ lsp#callbag#filter({_->mode() is# 'n'}),
        \ lsp#callbag#switchMap({_ -> s:send_highlight_request()}),
        \ lsp#callbag#filter({_->mode() is# 'n'}),
        \ lsp#callbag#subscribe({x->s:set_highlights(x)}),
        \)
endfunction

function! lsp#internal#highlight_references#_disable() abort
    if exists('s:Dispose') | call s:Dispose() | endif
endfunction

function! s:send_highlight_request() abort
    let l:capability = 'lsp#capabilities#has_document_highlight_provider(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if empty(l:servers)
        return lsp#callbag#empty()
    endif

    return lsp#request(l:servers[0], {
        \ 'method': 'textDocument/documentHighlight',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \  },
        \ })
endfunction

function! s:set_highlights(data) abort
    let l:bufnr = bufnr('%')

    call s:clear_highlights()

    if mode() != 'n' | return | endif

    if lsp#client#is_error(a:data) | return | endif

    " Get references from the response
    let l:reference_list = a:data['response']['result']
    if empty(l:reference_list)
        return
    endif

    " Convert references to vim positions
    let l:position_list = []
    for l:reference in l:reference_list
        call extend(l:position_list, lsp#utils#range#lsp_to_vim(l:bufnr, l:reference['range']))
    endfor

    call sort(l:position_list, function('s:compare_positions'))

    " Ignore response if the cursor is not over a reference anymore
    if s:in_reference(l:position_list) == -1 | return | endif

    " Store references
    let w:lsp_reference_positions = l:position_list
    let w:lsp_reference_matches = []

    " Apply highlights to the buffer
    call s:init_reference_highlight(l:bufnr)
    if s:use_vim_textprops
        for l:position in l:position_list
            call prop_add(l:position[0], l:position[1],
            \   {'id': s:prop_id,
            \    'bufnr': l:bufnr,
            \    'length': l:position[2],
            \    'type': 'vim-lsp-reference-highlight'})
            call add(w:lsp_reference_matches, l:position[0])
        endfor
    else
        for l:position in l:position_list
            let l:match = matchaddpos('lspReference', [l:position], -5)
            call add(w:lsp_reference_matches, l:match)
        endfor
    endif

    " Get references from the response
    echom 'highlight' . s:i . json_encode(l:position_list)
endfunction

function! s:clear_highlights() abort
    if exists('w:lsp_reference_matches')
        if s:use_vim_textprops
            let l:bufnr = bufnr()
            for l:line in w:lsp_reference_matches
                silent! call prop_remove(
                \   {'id': s:prop_id,
                \    'bufnr': l:bufnr,
                \    'all': v:true}, l:line)
            endfor
        else
            for l:match in w:lsp_reference_matches
                silent! call matchdelete(l:match)
            endfor
        endif
        unlet w:lsp_reference_matches
        unlet w:lsp_reference_positions
    endif
endfunction

" Compare two positions
function! s:compare_positions(p1, p2) abort
    let l:line_1 = a:p1[0]
    let l:line_2 = a:p2[0]
    if l:line_1 != l:line_2
        return l:line_1 > l:line_2 ? 1 : -1
    endif
    let l:col_1 = a:p1[1]
    let l:col_2 = a:p2[1]
    return l:col_1 - l:col_2
endfunction

" If the cursor is over a reference, return its index in
" the array. Otherwise, return -1.
function! s:in_reference(reference_list) abort
    let l:line = line('.')
    let l:column = col('.')
    let l:index = 0
    for l:position in a:reference_list
        if l:line == l:position[0] &&
        \  l:column >= l:position[1] &&
        \  l:column < l:position[1] + l:position[2]
            return l:index
        endif
        let l:index += 1
    endfor
    return -1
endfunction

function! s:init_reference_highlight(buf) abort
    if !empty(getbufvar(a:buf, 'lsp_did_reference_setup'))
        return
    endif

    if s:use_vim_textprops
        call prop_type_add('vim-lsp-reference-highlight', {
            \   'bufnr': a:buf,
            \   'highlight': 'lspReference',
            \   'combine': v:true
            \ })
    endif

    call setbufvar(a:buf, 'lsp_did_reference_setup', 1)
endfunction

" Cyclically move between references by `offset` occurrences.
function! lsp#internal#highlight_references#jump(offset) abort
    if !exists('w:lsp_reference_positions')
        echohl WarningMsg
        echom 'References not available'
        echohl None
        return
    endif

    " Get index of reference under cursor
    let l:index = s:in_reference(w:lsp_reference_positions)
    if l:index < 0
        return
    endif

    let l:n = len(w:lsp_reference_positions)
    let l:index += a:offset

    " Show a message when reaching TOP/BOTTOM of the file
    if l:index < 0
        echohl WarningMsg
        echom 'search hit TOP, continuing at BOTTOM'
        echohl None
    elseif l:index >= len(w:lsp_reference_positions)
        echohl WarningMsg
        echom 'search hit BOTTOM, continuing at TOP'
        echohl None
    endif

    " Wrap index
    if l:index < 0 || l:index >= len(w:lsp_reference_positions)
        let l:index = (l:index % l:n + l:n) % l:n
    endif

    " Jump
    let l:target = w:lsp_reference_positions[l:index][0:1]
    normal! m`
    call cursor(l:target[0], l:target[1])
endfunction
