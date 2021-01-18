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
        \       lsp#callbag#map({_->lsp#omni#get_managed_user_data_from_completed_item(v:event['completed_item'])}),
        \       lsp#callbag#filter({x->!empty(x)}),
        \       lsp#callbag#debounceTime(g:lsp_documentation_debounce),
        \       lsp#callbag#switchMap({user_data->
        \           lsp#callbag#pipe(
        \               s:resolve_completion(user_data),
        \               lsp#callbag#tap({user_data->s:show_floating_window(user_data)}),
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

let s:i = 0
function! s:resolve_completion(user_data) abort
    let l:completion_item = a:user_data['completion_item']
    if has_key(l:completion_item, 'documentation')
        return lsp#callbag#of(a:user_data)
    elseif lsp#capabilities#has_completion_resolve_provider(a:user_data['server_name'])
        return lsp#callbag#pipe(
            \ lsp#request(a:user_data['server_name'], {
            \   'method': 'completionItem/resolve',
            \   'params': l:completion_item,
            \ }),
            \ lsp#callbag#map({x->{
            \   'server_name': a:user_data['server_name'],
            \   'completion_item': x['response']['result'],
            \   'complete_position': a:user_data['complete_position'],
            \ }})
            \ )
    else
        return lsp#callbag#empty()
    endif
endfunction

function! s:show_floating_window(user_data) abort
    let l:completion_item = a:user_data['completion_item']
    echom json_encode(l:completion_item)
    let l:documentation = get(l:completion_item, 'documentation', '')
    if type(l:documentation) == type({}) && has_key(l:documentation, 'value')
        let l:documentation = l:documentation['value']
    endif
    if empty(l:documentation)
        return
    endif

    echom json_encode(l:documentation)
    if exists('s:floating_win')
        call s:floating_win.close()
    endif

    " TODO: support markdown
    let l:documentation = substitute(l:documentation, "\r", "", "g")
    let l:lines = split(l:documentation, "\n")

    " TODO: reuse floating window/buffer??
    let s:floating_win = s:FloatingWindow.new()
    call s:floating_win.set_bufnr(s:Buffer.create())
    call setbufline(s:floating_win.get_bufnr(), 1, l:lines)
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

