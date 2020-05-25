if exists('g:ctrlp_lsp_workspace_symbol_loaded')
    finish
endif
let g:ctrlp_lsp_workspace_symbol_loaded = 1

call add(g:ctrlp_ext_vars, {
    \ 'init': 'ctrlp#lsp#workspace_symbol#init()',
    \ 'change': 'ctrlp#lsp#workspace_symbol#change()',
    \ 'accept': 'ctrlp#lsp#workspace_symbol#accept',
    \ 'exit': 'ctrlp#lsp#workspace_symbol#exit()',
    \ 'lname': 'LspWorkspaceSymbol',
    \ 'sname': 'LspWrkSym',
    \ 'type': 'file',
    \ })

let s:id = g:ctrlp_builtins + len(g:ctrlp_ext_vars)
function! ctrlp#lsp#workspace_symbol#id() abort
    return s:id
endfunction

let s:reqid = 0
function! ctrlp#lsp#workspace_symbol#init() abort
endfunction

function! s:clear_timer() abort
    if exists('s:search_timer')
        call timer_stop(s:search_timer)
        unlet s:search_timer
    endif
endfunction

function! ctrlp#lsp#workspace_symbol#change() abort
    call s:clear_timer()
    let s:search_timer = timer_start(250, function('s:search'))
endfunction

function! s:search(...) abort
    let s:reqid += 1

    let l:input = ctrlp#input()

    if empty(l:input)
        call ctrlp#set([])
        call ctrlp#update()
        return
    endif

    let l:buf = bufnr('%') - 1
    let l:servers = filter(lsp#get_whitelisted_servers(l:buf), 'lsp#capabilities#has_workspace_symbol_provider(v:val)')
    let l:ctx = { 'reqid': s:reqid, 'items': [] }
    echom printf('Searching for "%s"', l:input)
    for l:server in l:servers
        call lsp#send_request(l:server, {
            \ 'bufnr': l:buf,
            \ 'method': 'workspace/symbol',
            \ 'params': {
            \   'query': l:input,
            \ },
            \ 'on_notification': function('s:handle_results', [l:server, l:ctx]),
            \ })
    endfor
endfunction

function! s:handle_results(server, ctx, data) abort
    if a:ctx['reqid'] != s:reqid
        return
    endif
    if lsp#client#is_error(a:data['response'])
        call lsp#utils#error('Failed to retrieve wokspace symbols.')
        return
    endif
    let l:list = lsp#ui#vim#utils#symbols_to_loc_list(a:server, a:data)
    for l:item in l:list
        call add(a:ctx['items'], printf('%s     %s', l:item['text'], l:item['filename']))
    endfor
    call ctrlp#set(a:ctx['items'])
    call ctrlp#update()
endfunction

function! ctrlp#lsp#workspace_symbol#exit() abort
    call s:clear_timer()
endfunction

function! ctrlp#lsp#workspace_symbol#accept(mode, str) abort
    echom a:str
    call ctrlp#exit()
endfunction
