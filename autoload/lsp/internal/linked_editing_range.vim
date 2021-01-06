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
    \         lsp#callbag#flatMap({ -> s:request_sync() }),
    \         lsp#callbag#subscribe({
    \           'next': { x -> call('s:prepare', x) }
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

    call lsp#callbag#pipe(
    \     s:request_sync(),
    \     lsp#callbag#subscribe({
    \         'next': { x -> call('s:prepare', x) },
    \         'error': { -> {} },
    \     })
    \ )
    return ''
endfunction

function! s:enabled(...) abort
    return g:lsp_linked_editing_range_enabled && s:TextMark.is_available()
endfunction

function! s:request_sync() abort
    let l:server = lsp#get_allowed_servers(&filetype)
    let l:server = filter(l:server, 'lsp#capabilities#has_linked_editing_range_provider(v:val)')
    let l:server = get(l:server, 0, v:null)
    if empty(l:server)
        return lsp#callbag#of([v:null])
    endif

    return lsp#callbag#of(
    \     lsp#callbag#pipe(
    \         lsp#request(l:server, {
    \             'method': 'textDocument/linkedEditingRange',
    \             'params': {
    \                 'textDocument': lsp#get_text_document_identifier(),
    \                 'position': lsp#get_position(),
    \             }
    \         }),
    \         lsp#callbag#toList()
    \     ).wait({ 'sleep': 1, 'timeout': 200 })
    \ )
endfunction

function! s:prepare(x) abort
    if empty(a:x) || empty(get(a:x, 'response')) || empty(get(a:x['response'], 'result')) || empty(get(a:x['response']['result'], 'ranges'))
        return
    endif

    call s:clear()
    call s:TextMark.set(bufnr('%'), s:TEXT_MARK_NAMESPACE, map(a:x['response']['result']['ranges'], { _, range -> {
    \     'range': range,
    \     'highlight': 'Underlined',
    \ } }))
    let s:state['bufnr'] = bufnr('%')
    let s:state['changenr'] = changenr()
    let s:state['changedtick'] = b:changedtick
endfunction

function! s:clear() abort
    call s:TextMark.clear(bufnr('%'), s:TEXT_MARK_NAMESPACE)
endfunction

function! s:sync() abort
    let l:bufnr = bufnr('%')
    if s:state['bufnr'] != l:bufnr
        return
    endif
    if s:state['changedtick'] == b:changedtick
        return
    endif
    if s:state['changenr'] > changenr()
        return
    endif

    " get current mark and related marks.
    let l:position = lsp#utils#position#vim_to_lsp('%', getpos('.')[1 : 2])
    let l:current_mark = v:null
    let l:related_marks = []
    for l:mark in s:TextMark.get(l:bufnr, s:TEXT_MARK_NAMESPACE)
        if lsp#utils#range#_contains(l:mark['range'], l:position)
            let l:current_mark = l:mark
        else
            let l:related_marks += [l:mark]
        endif
    endfor

    " ignore if current mark is not detected.
    if empty(l:current_mark)
        return
    endif

    " apply new text for related marks.
    let l:new_text = lsp#utils#range#_get_text(l:bufnr, l:current_mark['range'])
    call lsp#utils#text_edit#apply_text_edits(l:bufnr, map(l:related_marks, { _, mark -> {
    \     'range': mark['range'],
    \     'newText': l:new_text
    \ } }))

    " save state.
    let s:state['bufnr'] = l:bufnr
    let s:state['changenr'] = changenr()
    let s:state['changedtick'] = b:changedtick
endfunction
