" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#progress

let s:lsp_progress = {
      \ 'server': '',
      \ 'token': '',
      \ 'title': '',
      \ 'messages': '',
      \ 'percentage': 100,
      \ }

function! lsp#internal#work_done_progress#_enable() abort
    if !g:lsp_work_done_progress_enabled | return | endif

    let s:Dispose = lsp#callbag#pipe(
          \ lsp#stream(),
          \ lsp#callbag#filter({x->has_key(x, 'response') && has_key(x['response'], 'method')
          \  && x['response']['method'] ==# '$/progress' && has_key(x['response'], 'params')
          \  && has_key(x['response']['params'], 'value') && type(x['response']['params']['value']) == type({})}),
          \  lsp#callbag#subscribe({'next': function('s:handle_work_done_progress')})
          \ )
endfunction

function! s:handle_work_done_progress(progress) abort
    let l:value = a:progress['response']['params']['value']
    let s:lsp_progress['token'] = a:progress['response']['params']['token']
    let s:lsp_progress['server'] = a:progress['server']
    if l:value['kind'] ==# 'end'
        let s:lsp_progress['messages'] = ''
        let s:lsp_progress['percentage'] = 100
    elseif l:value['kind'] ==# 'begin'
        let s:lsp_progress['title'] = l:value['title']
    elseif l:value['kind'] ==# 'report'
        let s:lsp_progress['messages'] = get(l:value, 'message', '')
        let s:lsp_progress['percentage'] = get(l:value, 'percentage', '')
    endif
endfunction

function! lsp#internal#work_done_progress#_disable() abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! lsp#internal#work_done_progress#get_progress() abort
    return s:lsp_progress
endfunction
