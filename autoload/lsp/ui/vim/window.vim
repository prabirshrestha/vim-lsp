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
