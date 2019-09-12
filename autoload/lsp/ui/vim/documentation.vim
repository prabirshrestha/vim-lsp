let s:use_vim_popup = has('patch-8.1.1517') && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && has('nvim')

let s:last_popup_id = -1

function! s:show_documentation() abort
    call s:close_popup()

    if !has_key(v:completed_item, 'info') | return | endif

    let l:pum_pos = pum_getpos()
    let l:right = wincol() < winwidth(0) / 2

    " TODO: Neovim
    if l:right
        let l:line = l:pum_pos['row'] + 1
        let l:col = l:pum_pos['col'] + l:pum_pos['width'] + 1 + (l:pum_pos['scrollbar'] ? 1 : 0)
        let l:pos = 'topleft'
    else
        let l:line = l:pum_pos['row'] + 1
        let l:col = l:pum_pos['col'] - 1
        let l:pos = 'topright'
    endif

    " TODO: Support markdown
    let l:data = split(v:completed_item['info'], '\n')
    let l:lines = []
    let l:syntax_lines = []
    let l:ft = lsp#ui#vim#output#append(l:data, l:lines, l:syntax_lines)

    if s:use_vim_popup
        let s:last_popup_id = popup_create('(no documentation available)', {'line': l:line, 'col': l:col, 'pos': l:pos, 'padding': [0, 1, 0, 1]})
    elseif s:use_nvim_float
        " TODO
    endif

    call setbufvar(winbufnr(s:last_popup_id), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:last_popup_id), 'lsp_do_conceal', 1)
    call lsp#ui#vim#output#setcontent(s:last_popup_id, l:lines, l:ft)
endfunction

function! s:close_popup() abort
    if s:last_popup_id >= 0
        if s:use_vim_popup | call popup_close(s:last_popup_id) | endif
        if s:use_nvim_float | call nvim_win_close(s:last_popup_id, 1) | endif

        let s:last_popup_id = -1
    endif
endfunction

function! lsp#ui#vim#documentation#setup() abort
    augroup lsp_documentation_popup
        autocmd!
        autocmd CompleteChanged * call timer_start(0, {-> s:show_documentation()})
        autocmd CompleteDone * call s:close_popup()
    augroup end
endfunction
