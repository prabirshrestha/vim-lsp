let s:TextEdit = vital#lsp#import('VS.LSP.TextEdit')
let s:TextMark = vital#lsp#import('VS.Vim.Buffer.TextMark')

let s:TEXT_MARK_NAMESPACE = 'lsp#internal#linked_editing_range'

let s:state = {}
let s:state['bufnr'] = -1
let s:state['changenr'] = -1
let s:state['changedtick'] = -1

function! lsp#internal#linked_editing_range#_enable() abort
    if !s:enabled()
        return
    endif

    let s:Dispose = lsp#callbag#merge(
    \     lsp#callbag#pipe(
    \         lsp#callbag#fromEvent(['InsertEnter']),
    \         lsp#callbag#filter({ -> g:lsp_linked_editing_range_enabled }),
    \         lsp#callbag#switchMap({ -> lsp#callbag#of(s:request_sync()) }),
    \         lsp#callbag#subscribe({
    \           'next': { x -> s:prepare(x) }
    \         })
    \     ),
    \     lsp#callbag#pipe(
    \         lsp#callbag#fromEvent(['InsertLeave']),
    \         lsp#callbag#filter({ -> g:lsp_linked_editing_range_enabled }),
    \         lsp#callbag#subscribe({ -> s:clear() })
    \     ),
    \     lsp#callbag#pipe(
    \         lsp#callbag#fromEvent(['TextChanged', 'TextChangedI', 'TextChangedP']),
    \         lsp#callbag#filter({ -> g:lsp_linked_editing_range_enabled }),
    \         lsp#callbag#filter({ ->
    \           s:state.bufnr == bufnr('%') &&
    \           s:state.changedtick != b:changedtick &&
    \           s:state.changenr <= changenr()
    \         }),
    \         lsp#callbag#subscribe({ -> s:sync() })
    \     ),
    \ )
endfunction

function! lsp#internal#linked_editing_range#_disable() abort
    if exists('s:Dispose')
        call s:clear()
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! lsp#internal#linked_editing_range#prepare() abort
    if !s:enabled()
        return ''
    endif

    call s:prepare(s:request_sync())
    return ''
endfunction

function! s:enabled(...) abort
    return exists('##TextChangedP') && g:lsp_linked_editing_range_enabled && s:TextMark.is_available()
endfunction

function! s:request_sync() abort
    let l:server = lsp#get_allowed_servers(&filetype)
    let l:server = filter(l:server, 'lsp#capabilities#has_linked_editing_range_provider(v:val)')
    let l:server = get(l:server, 0, v:null)
    if empty(l:server)
        return v:null
    endif

    return lsp#callbag#pipe(
    \     lsp#request(l:server, {
    \         'method': 'textDocument/linkedEditingRange',
    \         'params': {
    \             'textDocument': lsp#get_text_document_identifier(),
    \             'position': lsp#get_position(),
    \         }
    \     }),
    \     lsp#callbag#toList(),
    \ ).wait({ 'wait': 1, 'timeout': 200 })[0]
endfunction

function! s:prepare(x) abort
    if empty(a:x) || empty(get(a:x, 'response')) || empty(get(a:x['response'], 'result')) || empty(get(a:x['response']['result'], 'ranges'))
        return
    endif
    let l:ranges = a:x['response']['result']['ranges']

    let l:bufnr = bufnr('%')
    let s:state['bufnr'] = l:bufnr
    let s:state['changenr'] = changenr()
    let s:state['changedtick'] = b:changedtick

    call s:clear()
    call s:TextMark.set(l:bufnr, s:TEXT_MARK_NAMESPACE, map(copy(l:ranges), { _, range -> {
    \     'start_pos': lsp#utils#position#lsp_to_vim(l:bufnr, range['start']),
    \     'end_pos': lsp#utils#position#lsp_to_vim(l:bufnr, range['end']),
    \     'highlight': 'Underlined',
    \ } }))

    " TODO: Force enable extmark's gravity option.
    if has('nvim')
        let l:new_text = lsp#utils#range#_get_text(l:bufnr, l:ranges[0])
        call s:TextEdit.apply(l:bufnr, map(copy(l:ranges), { _, range -> {
        \   'range': range,
        \   'newText': l:new_text,
        \ } }))
    endif
endfunction

function! s:clear() abort
    call s:TextMark.clear(bufnr('%'), s:TEXT_MARK_NAMESPACE)
endfunction

function! s:sync() abort
    " get current mark and related marks.
    let l:bufnr = bufnr('%')
    let l:pos = getpos('.')[1 : 2]
    let l:current_mark = v:null
    let l:related_marks = []
    for l:mark in s:TextMark.get(l:bufnr, s:TEXT_MARK_NAMESPACE)
        let l:start_pos = l:mark['start_pos']
        let l:end_pos = l:mark['end_pos']

        let l:contains = v:true
        let l:contains = l:contains && (l:start_pos[0] < l:pos[0] || l:start_pos[0] == l:pos[0] && l:start_pos[1] <= l:pos[1])
        let l:contains = l:contains && (l:end_pos[0] > l:pos[0] || l:end_pos[0] == l:pos[0] && l:end_pos[1] >= l:pos[1])
        if l:contains
            let l:current_mark = l:mark
        else
            let l:related_marks += [l:mark]
        endif
    endfor

    " ignore if current mark is not detected.
    if empty(l:current_mark)
        return
    endif

    " if new_text does not match to keyword pattern, we stop syncing and break undopoint.
    let l:new_text = lsp#utils#range#_get_text(l:bufnr, {
    \     'start': lsp#utils#position#vim_to_lsp('%', l:current_mark['start_pos']),
    \     'end': lsp#utils#position#vim_to_lsp('%', l:current_mark['end_pos']),
    \ })
    if l:new_text !~# '^\k*$'
        call s:clear()
        call feedkeys("\<C-G>u", 'n')
        return
    endif

    " apply new text for related marks.
    call lsp#utils#text_edit#apply_text_edits(l:bufnr, map(l:related_marks, { _, mark -> {
    \     'range': {
    \         'start': lsp#utils#position#vim_to_lsp('%', mark['start_pos']),
    \         'end': lsp#utils#position#vim_to_lsp('%', mark['end_pos']),
    \     },
    \     'newText': l:new_text
    \ } }))

    " save state.
    let s:state['bufnr'] = l:bufnr
    let s:state['changenr'] = changenr()
    let s:state['changedtick'] = b:changedtick
endfunction
