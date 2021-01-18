" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
let s:enabled = 0

let s:FloatingWindow = vital#lsp#import('VS.Vim.Window.FloatingWindow')
let s:Buffer = vital#lsp#import('VS.Vim.Buffer')

function! lsp#internal#completion#documentation#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_documentation_float | return | endif

    if !s:FloatingWindow.is_available() | return | endif
    if !exists('##CompleteChanged') | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent('CompleteChanged'),
        \       lsp#callbag#filter({_->g:lsp_documentation_float}),
        \       lsp#callbag#map({->copy(v:event)}),
        \       lsp#callbag#debounceTime(g:lsp_documentation_debounce),
        \       lsp#callbag#switchMap({event->
        \           lsp#callbag#pipe(
        \               s:resolve_completion(event),
        \               lsp#callbag#tap({managed_user_data->s:show_floating_window(event, managed_user_data)}),
        \               lsp#callbag#takeUntil(lsp#callbag#fromEvent('CompleteDone'))
        \           )
        \       })
        \   ),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent('CompleteDone'),
        \       lsp#callbag#tap({_->s:close_floating_window()}),
        \   )
        \ ),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! s:resolve_completion(event) abort
    let l:managed_user_data = lsp#omni#get_managed_user_data_from_completed_item(a:event['completed_item'])
    if empty(l:managed_user_data) | return lsp#callbag#empty() | endif

    let l:completion_item = l:managed_user_data['completion_item']

    if has_key(l:completion_item, 'documentation')
        return lsp#callbag#of(l:managed_user_data)
    elseif lsp#capabilities#has_completion_resolve_provider(l:managed_user_data['server_name'])
        return lsp#callbag#pipe(
            \ lsp#request(l:managed_user_data['server_name'], {
            \   'method': 'completionItem/resolve',
            \   'params': l:completion_item,
            \ }),
            \ lsp#callbag#map({x->{
            \   'server_name': l:managed_user_data['server_name'],
            \   'completion_item': x['response']['result'],
            \   'complete_position': l:managed_user_data['complete_position'],
            \ }})
            \ )
    else
        return lsp#callbag#empty()
    endif
endfunction

function! s:show_floating_window(event, managed_user_data) abort
    let l:completion_item = a:managed_user_data['completion_item']
    let l:documentation = get(l:completion_item, 'documentation', '')
    if type(l:documentation) == type({}) && has_key(l:documentation, 'value')
        let l:documentation = l:documentation['value']
    endif
    if empty(l:documentation)
        return
    endif

    if exists('s:floating_win')
        call s:floating_win.close()
    endif

    " TODO: support markdown
    let l:lines = lsp#utils#_split_by_eol(l:documentation)

    let l:row = float2nr(a:event['row'])
    let l:col = float2nr(a:event['col'])
    let l:curpos = screenrow()

    " TODO: reuse floating window/buffer??
    let s:floating_win = s:FloatingWindow.new()
    let l:bufnr = s:Buffer.create()
    call setbufline(l:bufnr, 1, l:lines)
    call s:floating_win.set_bufnr(l:bufnr)

    call s:floating_win.open({
        \ 'row': 1,
        \ 'col': 1,
        \ 'width': 10,
        \ 'height': 10,
        \ })
endfunction

function! s:close_floating_window() abort
    if exists('s:floating_win')
        call s:floating_win.close()
    endif
endfunction

function! lsp#internal#completion#documentation#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction

function! s:log(x) abort
    echom json_encode(a:x)
endfunction

