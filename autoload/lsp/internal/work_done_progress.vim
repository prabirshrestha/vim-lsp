" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#progress

let s:progress_ui = []
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
    " Add the server name to distinguish the server
    let l:token = a:server . ':' . a:progress['params']['token']
    let l:new = {
      \ 'server': a:server,
      \ 'token': l:token,
      \ 'title': '',
      \ 'messages': '',
      \ 'percentage': -1,
      \ }

    if l:value['kind'] ==# 'end'
        let l:new['messages'] = ''
        let l:new['percentage'] = 100.0
        let s:progress_ui = filter(s:progress_ui, {_, x->x['token'] !=# l:token})
    elseif l:value['kind'] ==# 'begin'
        let l:new['title'] = l:value['title']
        let s:progress_ui = filter(s:progress_ui, {_, x->x['token'] !=# l:token})->insert(l:new)
    elseif l:value['kind'] ==# 'report'
        let l:new['messages'] = get(l:value, 'message', '')
        let l:new['percentage'] = get(l:value, 'percentage', -1.0)
        let l:idx = match(s:progress_ui, l:token)
        let l:new['title'] = s:progress_ui[l:idx]['title']
        let s:progress_ui = filter(s:progress_ui, {_, x->x['token'] !=# l:token})->insert(l:new)
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
    return s:progress_ui
endfunction
