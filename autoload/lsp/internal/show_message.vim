let s:ErrorType = 1
let s:WarningType = 2
let s:InfoType = 3
let s:LogType = 4

function! lsp#internal#show_message#_enable() abort
    if g:lsp_show_message_log_level ==# 'none' | return | endif
    let s:Dispose = lsp#callbag#pipe(
            \ lsp#stream(),
            \ lsp#callbag#filter({x->
            \   g:lsp_show_message_log_level !=# 'none' &&
            \   has_key(x, 'response') && has_key(x['response'], 'method')
            \   && x['response']['method'] ==# 'window/showMessage'
            \ }),
            \ lsp#callbag#tap({x->s:handle_show_message(x['server'], x['response']['params'])}),
            \ lsp#callbag#subscribe({ 'error': function('s:on_error') }),
            \ )
endfunction

function! lsp#internal#show_message#_disable() abort
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:on_error(e) abort
    call lsp#log('lsp#internal#show_message error', a:e)
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:handle_show_message(server, params) abort
    let l:level = s:name_to_level(g:lsp_show_message_log_level)
    let l:type = a:params['type']
    if l:level < l:type
        return
    endif

    let l:message = a:params['message']
    try
        if l:type == s:ErrorType
            echohl ErrorMsg
        elseif l:type == s:WarningType
            echohl WarningMsg
        endif
        echom printf('%s: %s: %s', a:server, s:type_to_name(l:type), l:message)
    finally
        echohl None
    endtry
endfunction

function! s:name_to_level(name) abort
    if a:name ==# 'none'
        return 0
    elseif a:name ==# 'error'
        return s:ErrorType
    elseif a:name ==# 'warn' || a:name ==# 'warning'
        return s:WarningType
    elseif a:name ==# 'info'
        return s:InfoType
    elseif a:name ==# 'log'
        return s:LogType
    else
        return 0
    endif
endfunction

function! s:type_to_name(type) abort
    return get(['unknown', 'error', 'warning', 'info', 'log'], a:type, 'unknown')
endfunction

