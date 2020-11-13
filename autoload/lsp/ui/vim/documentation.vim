let s:use_vim_popup = has('patch-8.1.1517') && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && has('nvim')

let s:last_popup_id = -1
let s:last_timer_id = v:false

function! s:complete_changed() abort
    if !g:lsp_documentation_float | return | endif
    " Use a timer to avoid textlock (see :h textlock).
    let l:event = copy(v:event)
    if s:last_timer_id
        call timer_stop(s:last_timer_id)
        let s:last_timer_id = v:false
    endif
    let s:last_timer_id = timer_start(g:lsp_documentation_debounce, {-> s:show_documentation(l:event)})
endfunction

function! s:show_documentation(event) abort
    call s:close_popup()

    if !has_key(a:event['completed_item'], 'info') || empty(a:event['completed_item']['info'])
        return
    endif


    " TODO: Support markdown
    let l:data = split(a:event['completed_item']['info'], '\n')
    let l:lines = []
    let l:syntax_lines = []
    let l:ft = lsp#ui#vim#output#append(l:data, l:lines, l:syntax_lines)


   " Neovim
   if s:use_nvim_float
        let l:event = a:event
        let l:event.row = float2nr(l:event.row)
        let l:event.col = float2nr(l:event.col)

        let l:buffer = nvim_create_buf(v:false, v:true)
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
                let l:row = &lines - &cmdheight - 1
                let l:height = min([l:height, &lines - &cmdheight - l:event.row - l:event.height])
            else " dock upwards
                let l:anchor = 'NW'
                let l:row = 0
                let l:height = min([l:height, l:event.row - 1])
            endif

        else " not docked
            let l:row = l:event['row']
            let l:height = max([&lines - &cmdheight - l:row, &previewheight])

            let l:right_area = &columns - l:event.col - l:event.width + 1   " 1 for the padding of popup
            let l:left_area = l:event.col - 1
            let l:right = l:right_area > l:left_area
            if l:right
                let l:anchor = 'NW'
                let l:width = l:right_area - 1
                let l:col = l:event.col + l:event.width + (l:event.scrollbar ? 1 : 0)
            else
                let l:anchor = 'NE'
                let l:width = l:left_area
                let l:col = l:event.col - 1     " 1 due to padding of completion popup
            endif
        endif

        call setbufvar(l:buffer, 'lsp_syntax_highlights', l:syntax_lines)
        call setbufvar(l:buffer, 'lsp_do_conceal', 1)

        " add padding on both sides of lines containing text
        for l:index in range(len(l:lines))
            if len(l:lines[l:index]) > 0
                let l:lines[l:index] = ' ' . l:lines[l:index] . ' '
            endif
        endfor

        call nvim_buf_set_lines(l:buffer, 0, -1, v:false, l:lines)
        call nvim_buf_set_option(l:buffer, 'readonly', v:true)
        call nvim_buf_set_option(l:buffer, 'modifiable', v:false)
        call nvim_buf_set_option(l:buffer, 'filetype', l:ft.'.lsp-hover')

        if !g:lsp_documentation_float_docked
            let l:bufferlines = nvim_buf_line_count(l:buffer)
            let l:maxwidth = max(map(getbufline(l:buffer, 1, '$'), 'strdisplaywidth(v:val)'))
            if g:lsp_preview_max_width > 0
                let l:maxwidth = min([g:lsp_preview_max_width, l:maxwidth])
            endif
            let l:width = min([float2nr(l:width), l:maxwidth])
            let l:height = min([float2nr(l:height), l:bufferlines])
        endif
        if g:lsp_preview_max_height > 0
            let l:maxheight = g:lsp_preview_max_height
            let l:height = min([l:height, l:maxheight])
        endif

        " Height and width must be atleast 1, otherwise error
        let l:height = (l:height < 1 ? 1 : l:height)
        let l:width = (l:width < 1 ? 1 : l:width)

        let s:last_popup_id = nvim_open_win(l:buffer, v:false, {'relative': 'editor', 'anchor': l:anchor, 'row': l:row, 'col': l:col, 'height': l:height, 'width': l:width, 'style': 'minimal'})
        return
    endif

    " Vim
    let l:current_win_id = win_getid()

    let l:right = wincol() < winwidth(0) / 2
    if l:right
        let l:line = a:event['row'] + 1
        let l:col = a:event['col'] + a:event['width'] + 1 + (a:event['scrollbar'] ? 1 : 0)
    else
        let l:line = a:event['row'] + 1
        let l:col = a:event['col'] - 1
    endif
    let s:last_popup_id = popup_create('(no documentation available)', {'line': l:line, 'col': l:col, 'pos': l:right ? 'topleft' : 'topright', 'padding': [0, 1, 0, 1]})
    call setbufvar(winbufnr(s:last_popup_id), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:last_popup_id), 'lsp_do_conceal', 1)
    call lsp#ui#vim#output#setcontent(s:last_popup_id, l:lines, l:ft)
    call win_gotoid(l:current_win_id)
endfunction

function! s:close_popup() abort
    if s:last_timer_id
        call timer_stop(s:last_timer_id)
        let s:last_timer_id = v:false
    endif
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
            autocmd CompleteChanged * call s:complete_changed()
        endif
        autocmd CompleteDone * call s:close_popup()
    augroup end
endfunction

" vim: et ts=4
