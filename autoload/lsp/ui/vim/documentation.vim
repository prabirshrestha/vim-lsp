let s:use_vim_popup = has('patch-8.1.1517') && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && has('nvim')

let s:last_popup_id = -1

function! s:complete_done() abort
    if !g:lsp_documentation_float | return | endif
    " Use a timer to avoid textlock (see :h textlock).
    let l:event = deepcopy(v:event)
    call timer_start(0, {-> s:show_documentation(l:event)})
endfunction

function! s:show_documentation(event) abort
    call s:close_popup()

    if !has_key(a:event['completed_item'], 'info') || empty(a:event['completed_item']['info'])
        return
    endif

    let l:right = wincol() < winwidth(0) / 2

    " TODO: Neovim
    if l:right
        let l:line = a:event['row'] + 1
        let l:col = a:event['col'] + a:event['width'] + 1 + (a:event['scrollbar'] ? 1 : 0)
    else
        let l:line = a:event['row'] + 1
        let l:col = a:event['col'] - 1
    endif

    " TODO: Support markdown
    let l:data = split(a:event['completed_item']['info'], '\n')
    let l:lines = []
    let l:syntax_lines = []
    let l:ft = lsp#ui#vim#output#append(l:data, l:lines, l:syntax_lines)

    let l:current_win_id = win_getid()

    if s:use_vim_popup
        let s:last_popup_id = popup_create('(no documentation available)', {'line': l:line, 'col': l:col, 'pos': l:right ? 'topleft' : 'topright', 'padding': [0, 1, 0, 1]})
    elseif s:use_nvim_float
        let l:height = float2nr(winheight(0) - l:line + 1)
        let l:width = float2nr(l:right ? winwidth(0) - l:col + 1 : l:col)
        if l:width <= 0
          let l:width = 1
        endif
        if l:height <= 0
          let l:height = 1
        endif
        let s:last_popup_id = lsp#ui#vim#output#floatingpreview([])
        call nvim_win_set_config(s:last_popup_id, {'relative': 'win', 'anchor': l:right ? 'NW' : 'NE', 'row': l:line - 1, 'col': l:col - 1, 'height': l:height, 'width': l:width})
    endif

    call setbufvar(winbufnr(s:last_popup_id), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:last_popup_id), 'lsp_do_conceal', 1)
    call lsp#ui#vim#output#setcontent(s:last_popup_id, l:lines, l:ft)
    let [l:bufferlines, l:maxwidth] = lsp#ui#vim#output#get_size_info()

    call win_gotoid(l:current_win_id)

    if s:use_nvim_float
        call lsp#ui#vim#output#adjust_float_placement(l:bufferlines, l:maxwidth)
        call nvim_win_set_config(s:last_popup_id, {'relative': 'win', 'row': l:line - 1, 'col': l:col - 1})
    endif
endfunction

function! s:close_popup() abort
    if s:last_popup_id >= 0
        if s:use_vim_popup | call popup_close(s:last_popup_id) | endif
        if s:use_nvim_float && nvim_win_is_valid(s:last_popup_id) | call nvim_win_close(s:last_popup_id, 1) | endif

        let s:last_popup_id = -1
    endif
endfunction

function! lsp#ui#vim#documentation#setup() abort
    augroup lsp_documentation_popup
        autocmd!
        autocmd CompleteChanged * call s:complete_done()
        autocmd CompleteDone * call s:close_popup()
    augroup end
endfunction
