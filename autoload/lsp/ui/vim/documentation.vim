let s:use_vim_popup = has('patch-8.1.1517') && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && has('nvim')

let s:last_popup_id = -1

function! s:complete_done() abort
    if !g:lsp_documentation_float | return | endif
    " Use a timer to avoid textlock (see :h textlock).
    let l:event = copy(v:event)
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
        let s:last_popup_id = lsp#ui#vim#output#floatingpreview([])

        let l:curpos = win_screenpos(nvim_get_current_win())[0] + winline() - 1
        let g:lsp_documentation_float_docked = get(g:, 'lsp_documentation_float_docked', 0)

        if g:lsp_documentation_float_docked
            let g:lsp_documentation_float_docked_maxheight = get(g:, ':lsp_documentation_float_docked_maxheight', &previewheight)
            let l:dock_downwards = max([screenrow(), l:curpos]) < (&lines / 2)
            let l:height = min([len(l:data), g:lsp_documentation_float_docked_maxheight])
            let l:width = &columns
            let l:col = 0
            if l:dock_downwards
                let l:anchor = 'SW'
                let l:row = &lines
                let l:height = min([l:height, &lines - &cmdheight - a:event.row])
            else " dock upwards
                let l:anchor = 'NW'
                let l:row = 0
                let l:height = min([l:height, a:event.row - 1])
            endif

        else " not docked
            let l:row = a:event['row'] + 1
            let l:height = max([&lines - &cmdheight -l:row, &previewheight])

            let l:right_area = &columns - a:event.col - a:event.width + 1   " 1 for the padding of popup
            let l:left_area = a:event.col - 1
            let l:right = l:right_area > l:left_area

            if l:right
                let l:anchor = 'NW'
                let l:width = l:right_area - 1
                let l:col = a:event.col + a:event.width + 1

            else
                let l:anchor = 'NE'
                let l:width = l:left_area
                let l:col = a:event.col
            endif
        endif


        call nvim_win_set_config(s:last_popup_id, {'relative': 'editor', 'anchor': l:anchor, 'row': l:row, 'col': l:col, 'height': l:height, 'width': l:width})
    endif

    call setbufvar(winbufnr(s:last_popup_id), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:last_popup_id), 'lsp_do_conceal', 1)
    call lsp#ui#vim#output#setcontent(s:last_popup_id, l:lines, l:ft)
    let [l:bufferlines, l:maxwidth] = lsp#ui#vim#output#get_size_info()

    call win_gotoid(l:current_win_id)

    if s:use_nvim_float
        if !g:lsp_documentation_float_docked
            call lsp#ui#vim#output#adjust_float_placement(l:bufferlines, l:maxwidth)
        endif
        call nvim_win_set_config(s:last_popup_id, {'relative': 'editor', 'row': l:row - 1, 'col': l:col - 1})
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
        if exists('##CompleteChanged')
            autocmd CompleteChanged * call s:complete_done()
        endif
        autocmd CompleteDone * call s:close_popup()
    augroup end
endfunction
