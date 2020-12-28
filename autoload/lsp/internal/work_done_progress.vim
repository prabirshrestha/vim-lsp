" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#progress

let s:lsp_progress = {
      \ 'server': '',
      \ 'token': '',
      \ 'title': '',
      \ 'messages': '',
      \ 'percentage': 100,
      \ }
let s:enabled = 0

function! lsp#internal#work_done_progress#_enable() abort
    if !g:lsp_work_done_progress_enabled | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    let s:Dispose = lsp#callbag#pipe(
          \ lsp#stream(),
          \ lsp#callbag#filter({x->has_key(x, 'response') && has_key(x['response'], 'method')
          \  && x['response']['method'] ==# '$/progress' && has_key(x['response'], 'params')
          \  && has_key(x['response']['params'], 'value') && type(x['response']['params']['value']) == type({})}),
          \  lsp#callbag#subscribe({'next': {x->s:handle_work_done_progress(x['server'], x['response'])}})
          \ )
endfunction

function! s:handle_work_done_progress(server, progress) abort
    let l:value = a:progress['params']['value']
    let s:lsp_progress['token'] = a:progress['params']['token']
    let s:lsp_progress['server'] = a:server
    if l:value['kind'] ==# 'end'
        let s:lsp_progress['messages'] = ''
        let s:lsp_progress['percentage'] = 100.0
    elseif l:value['kind'] ==# 'begin'
        let s:lsp_progress['title'] = l:value['title']
    elseif l:value['kind'] ==# 'report'
        let s:lsp_progress['messages'] = get(l:value, 'message', '')
        let s:lsp_progress['percentage'] = get(l:value, 'percentage', -1.0)
    endif
endfunction

function! lsp#internal#work_done_progress#_disable() abort
    if !s:enabled | return | endif

    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif

    let s:enabled = 0
endfunction

function! lsp#internal#work_done_progress#get_progress() abort
    return s:lsp_progress
endfunction
