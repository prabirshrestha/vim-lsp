function! s:echo_begin(type)
  if a:type == 1
    echohl ErrorMsg
  elseif a:type == 2
    echohl WarningMsg
  elseif a:type == 3
    echohl None  " info
  elseif a:type == 4
    echohl None  " log
  endif
endfunction

function! s:echo_end()
  echohl None
endfunction

function! lsp#ui#vim#window#log_message(type, message) abort
  call s:echo_begin(a:type)
  echo a:message
  call s:echo_end()
endfunction

function! lsp#ui#vim#window#show_message_request(type, message, actions) abort
    if empty(a:actions)
      return v:null
    endif

    let l:options = [a:message]
    let l:i = 0
    for l:action in a:actions
        let l:i = l:i + 1
        call add(l:options, l:i.'. '.l:action['title'])
    endfor

    let l:answer = inputlist(l:options)
    if l:answer < 1 || l:answer > len(a:actions)
        return v:null
    endif
    return a:actions[l:answer-1]
endfunction
