let s:Markdown = vital#lsp#import('VS.Vim.Syntax.Markdown')
let s:Window = vital#lsp#import('VS.Vim.Window')

function! lsp#internal#ui#popupmenu#open(opt) abort
    let l:Callback = remove(a:opt, 'callback')
    let l:items = remove(a:opt, 'items')

    let l:items_with_shortcuts= map(l:items, {
        \   idx, item -> ((idx < 9) ? '['.(idx+1).'] ' : '').item
        \ })

    function! Filter(id, key) abort closure
        if a:key >= 1 && a:key <= len(l:items)
            call popup_close(a:id, a:key)
        elseif a:key ==# "\<C-j>"
            call win_execute(a:id, 'normal! j')
        elseif a:key ==# "\<C-k>"
            call win_execute(a:id, 'normal! k')
        else
            return popup_filter_menu(a:id, a:key)
        endif

        return v:true
    endfunction

    let l:popup_opt = extend({
        \   'callback': funcref('s:callback', [l:Callback]),
        \   'filter': funcref('Filter'),
        \ }, a:opt)

    let l:winid = popup_menu(l:items_with_shortcuts, l:popup_opt)
    call s:Window.do(l:winid, { -> s:Markdown.apply() })
    execute('doautocmd <nomodeline> User lsp_float_opened')
endfunction

function! s:callback(callback, id, selected) abort
    call a:callback(a:id, a:selected)
    execute('doautocmd <nomodeline> User lsp_float_closed')
endfunction
