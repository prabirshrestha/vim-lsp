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

  let l:prompt = a:message."\n\n"
  let l:prompt .= "0. <cancel>\n"
  let l:i = 0

  while l:i < len(a:actions)
    let l:prompt .= (l:i+1).'. '.a:actions[l:i]["title"]."\n"
    let l:i += 1
  endwhile

  let l:prompt .= "\n> "

  while 1
    call s:echo_begin(a:type)
    let l:answer = input(l:prompt)
    call s:echo_end()
    if l:answer == '0'
      return v:null
    endif
    let l:parsed_answer = str2nr(l:answer)
    if l:parsed_answer > 0 && l:parsed_answer <= len(a:actions)
      return a:actions[l:parsed_answer-1]
    endif

    echo "\n\n"
  endwhile
endfunction
