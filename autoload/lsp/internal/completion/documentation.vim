" https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
let s:enabled = 0

let s:Markdown = vital#lsp#import('VS.Vim.Syntax.Markdown')
let s:MarkupContent = vital#lsp#import('VS.LSP.MarkupContent')
let s:FloatingWindow = vital#lsp#import('VS.Vim.Window.FloatingWindow')
let s:Window = vital#lsp#import('VS.Vim.Window')
let s:Buffer = vital#lsp#import('VS.Vim.Buffer')

function! lsp#internal#completion#documentation#_enable() abort
    " don't even bother registering if the feature is disabled
    if !g:lsp_completion_documentation_enabled | return | endif

    if !s:FloatingWindow.is_available() | return | endif
    if !exists('##CompleteChanged') | return | endif

    if s:enabled | return | endif
    let s:enabled = 1

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent('CompleteChanged'),
        \       lsp#callbag#filter({_->g:lsp_completion_documentation_enabled}),
        \       lsp#callbag#map({->copy(v:event)}),
        \       lsp#callbag#debounceTime(g:lsp_completion_documentation_delay),
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
        \       lsp#callbag#tap({_->s:close_floating_window(v:false)}),
        \   )
        \ ),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! s:resolve_completion(event) abort
    let l:managed_user_data = lsp#omni#get_managed_user_data_from_completed_item(a:event['completed_item'])
    if empty(l:managed_user_data)
        return lsp#callbag#of({})
    endif

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
        return lsp#callbag#of({})
    endif
endfunction

function! s:show_floating_window(event, managed_user_data) abort
    if empty(a:managed_user_data) || !pumvisible()
        call s:close_floating_window(v:true)
        return
    endif
    let l:completion_item = a:managed_user_data['completion_item']

    let l:contents = []

    " Add detail field if provided.
    if type(get(l:completion_item, 'detail', v:null)) == type('')
        if !empty(l:completion_item.detail)
            let l:detail = s:MarkupContent.normalize({
            \     'language': &filetype,
            \     'value': l:completion_item['detail'],
            \ })
            let l:contents += [l:detail]
        endif
    endif

    " Add documentation filed if provided.
    let l:documentation = s:MarkupContent.normalize(get(l:completion_item, 'documentation', ''))
    if !empty(l:documentation)
        let l:contents += [l:documentation]
    endif

    " Ignore if contents is empty.
    if empty(l:contents)
        return s:close_floating_window(v:true)
    endif

    " Update contents.
    let l:doc_win = s:get_doc_win()
    call deletebufline(l:doc_win.get_bufnr(), 1, '$')
    call setbufline(l:doc_win.get_bufnr(), 1, lsp#utils#_split_by_eol(join(l:contents, "\n\n")))

    " Calculate layout.
    let l:layout = s:get_layout(a:event)
    if empty(l:layout)
        return s:close_floating_window(v:true)
    endif

    " Show popupmenu and apply markdown syntax.
    call l:doc_win.open({
    \     'row': l:layout.row,
    \     'col': l:layout.col,
    \     'width': l:layout.width,
    \     'height': l:layout.height,
    \     'topline': 1,
    \ })
    call s:Window.do(l:doc_win.get_winid(), { -> s:Markdown.apply() })
endfunction

function! s:close_floating_window(force) abort
    " Ignore `CompleteDone` if it occurred by `complete()` because in this case, the popup menu will re-appear immediately.
    let l:ctx = {}
    function! l:ctx.callback(force) abort
        if !pumvisible() || a:force
            call s:get_doc_win().close()
        endif
    endfunction
    call timer_start(1, { -> l:ctx.callback(a:force) })
endfunction

function! s:get_layout(event) abort
    let l:size = s:get_doc_win().get_size({
    \   'maxwidth': float2nr(&columns * 0.4),
    \   'maxheight': float2nr(&lines - a:event.row - 1),
    \ })

    let l:col_if_right = a:event.col + a:event.width + 1 + (a:event.scrollbar ? 1 : 0)
    let l:col_if_left = a:event.col - l:size.width - 2

    if l:size.width >= (&columns - l:col_if_right)
        let l:col = l:col_if_left
    else
        let l:col = l:col_if_right
    endif

    " Has no enough space for left/right both.
    if l:col <= 0
        return {}
    endif
    if &columns <= l:col + l:size.width
        return {}
    endif

    return extend(l:size, {
    \   'row': float2nr(a:event.row + 1),
    \   'col': float2nr(l:col + 1),
    \ })
endfunction

function! s:get_doc_win() abort
    if exists('s:doc_win')
        return s:doc_win
    endif

    let s:doc_win = s:FloatingWindow.new({
    \   'on_opened': { -> execute('doautocmd <nomodeline> User lsp_float_opened') },
    \   'on_closed': { -> execute('doautocmd <nomodeline> User lsp_float_closed') }
    \ })
    call s:doc_win.set_var('&wrap', 1)
    call s:doc_win.set_var('&conceallevel', 2)
    call s:doc_win.set_bufnr(s:Buffer.create())
    call setbufvar(s:doc_win.get_bufnr(), '&buftype', 'nofile')
    call setbufvar(s:doc_win.get_bufnr(), '&bufhidden', 'hide')
    call setbufvar(s:doc_win.get_bufnr(), '&buflisted', 0)
    return s:doc_win
endfunction

function! lsp#internal#completion#documentation#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
endfunction
