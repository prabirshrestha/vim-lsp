let s:use_vim_popup = has('patch-8.1.1517') && g:lsp_preview_float && !has('nvim')
let s:use_nvim_float = exists('*nvim_open_win') && g:lsp_preview_float && has('nvim')
let s:use_preview = !s:use_vim_popup && !s:use_nvim_float

let s:winid = v:false
let s:prevwin = v:false
let s:preview_data = v:false

function! s:vim_popup_closed(...) abort
    let s:preview_data = v:false
endfunction

function! lsp#ui#vim#output#closepreview() abort
    if win_getid() ==# s:winid
        " Don't close if window got focus
        return
    endif
    "closing floats in vim8.1 must use popup_close() (nvim could use nvim_win_close but pclose
    "works)
    if s:use_vim_popup && s:winid
        call popup_close(s:winid)
    else
        pclose
    endif
    let s:winid = v:false
    let s:preview_data = v:false
    augroup lsp_float_preview_close
    augroup end
    autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
    doautocmd User lsp_float_closed
endfunction

function! lsp#ui#vim#output#focuspreview() abort
    if s:is_cmdwin()
        return
    endif

    " This does not work for vim8.1 popup but will work for nvim and old preview
    if s:winid
        if win_getid() !=# s:winid
            let s:prevwin = win_getid()
            call win_gotoid(s:winid)
        elseif s:prevwin
            " Temporarily disable hooks
            " TODO: remove this when closing logic is able to distinguish different move directions
            autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
            call win_gotoid(s:prevwin)
            call s:add_float_closing_hooks()
            let s:prevwin = v:false
        endif
    endif
endfunction

function! s:bufwidth() abort
    let l:width = winwidth(0)
    let l:numberwidth = max([&numberwidth, strlen(line('$'))+1])
    let l:numwidth = (&number || &relativenumber)? l:numberwidth : 0
    let l:foldwidth = &foldcolumn

    if &signcolumn ==? 'yes'
        let l:signwidth = 2
    elseif &signcolumn ==? 'auto'
        let l:signs = execute(printf('sign place buffer=%d', bufnr('')))
        let l:signs = split(l:signs, "\n")
        let l:signwidth = len(l:signs)>2? 2: 0
    else
        let l:signwidth = 0
    endif
    return l:width - l:numwidth - l:foldwidth - l:signwidth
endfunction


function! s:get_float_positioning(height, width) abort
    let l:height = a:height
    let l:width = a:width
    " For a start show it below/above the cursor
    " TODO: add option to configure it 'docked' at the bottom/top/right
    let l:y = winline()
    if l:y + l:height >= winheight(0)
        " Float does not fit
        if l:y > l:height
            " Fits above
            let l:y = winline() - l:height - 1
        elseif l:y - 2 > winheight(0) - l:y
            " Take space above cursor
            let l:y = 1
            let l:height = winline()-2
        else
            " Take space below cursor
            let l:height = winheight(0) -l:y
        endif
    endif
    let l:col = col('.')
    let l:style = 'minimal'
    " Positioning is not window but screen relative
    let l:opts = {
        \ 'relative': 'win',
        \ 'row': l:y,
        \ 'col': l:col,
        \ 'width': l:width,
        \ 'height': l:height,
        \ 'style': l:style,
        \ }
    return l:opts
endfunction

function! lsp#ui#vim#output#floatingpreview(data) abort
    if s:use_nvim_float
        let l:buf = nvim_create_buf(v:false, v:true)
        call setbufvar(l:buf, '&signcolumn', 'no')

        " Try to get as much space around the cursor, but at least 10x10
        let l:width = max([s:bufwidth(), 10])
        let l:height = max([&lines - winline() + 1, winline() - 1, 10])

        if g:lsp_preview_max_height > 0
            let l:height = min([g:lsp_preview_max_height, l:height])
        endif

        let l:opts = s:get_float_positioning(l:height, l:width)

        let s:winid = nvim_open_win(l:buf, v:true, l:opts)
        call nvim_win_set_option(s:winid, 'winhl', 'Normal:Pmenu,NormalNC:Pmenu')
        call nvim_win_set_option(s:winid, 'foldenable', v:false)
        call nvim_win_set_option(s:winid, 'wrap', v:true)
        call nvim_win_set_option(s:winid, 'statusline', '')
        call nvim_win_set_option(s:winid, 'number', v:false)
        call nvim_win_set_option(s:winid, 'relativenumber', v:false)
        call nvim_win_set_option(s:winid, 'cursorline', v:false)
        " Enable closing the preview with esc, but map only in the scratch buffer
        nmap <buffer><silent> <esc> :pclose<cr>
    elseif s:use_vim_popup
        let l:options = {
            \ 'moved': 'any',
            \ 'border': [1, 1, 1, 1],
            \ 'callback': function('s:vim_popup_closed')
            \ }

        if g:lsp_preview_max_width > 0
            let l:options['maxwidth'] = g:lsp_preview_max_width
        endif

        if g:lsp_preview_max_height > 0
            let l:options['maxheight'] = g:lsp_preview_max_height
        endif

        let s:winid = popup_atcursor('...', l:options)
    endif
    return s:winid
endfunction

function! lsp#ui#vim#output#setcontent(winid, lines, ft) abort
    if s:use_vim_popup
        " vim popup
        call setbufline(winbufnr(a:winid), 1, a:lines)
        call win_execute(s:winid, 'setlocal filetype=' . a:ft . '.lsp-hover')
    else
        " nvim floating or preview
        call setline(1, a:lines)
        setlocal readonly nomodifiable
        silent! let &l:filetype = a:ft . '.lsp-hover'
    endif
endfunction

function! lsp#ui#vim#output#adjust_float_placement(bufferlines, maxwidth) abort
    if s:use_nvim_float
        let l:win_config = {}
        let l:height = min([winheight(s:winid), a:bufferlines])
        let l:width = min([winwidth(s:winid), a:maxwidth])
        let l:win_config = s:get_float_positioning(l:height, l:width)
        call nvim_win_set_config(s:winid, l:win_config )
    endif
endfunction

function! s:add_float_closing_hooks() abort
    if g:lsp_preview_autoclose
        augroup lsp_float_preview_close
            autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
            autocmd CursorMoved,CursorMovedI,VimResized * call lsp#ui#vim#output#closepreview()
        augroup END
    endif
endfunction

function! lsp#ui#vim#output#getpreviewwinid() abort
    return s:winid
endfunction

function! s:open_preview(data) abort
    if s:use_vim_popup || s:use_nvim_float
        let l:winid = lsp#ui#vim#output#floatingpreview(a:data)
    else
        execute &previewheight.'new'
        let l:winid = win_getid()
    endif
    return l:winid
endfunction

function! s:set_cursor(current_window_id, options) abort
    if !has_key(a:options, 'cursor')
        return
    endif

    if s:use_nvim_float
        " Neovim floats
        " Go back to the preview window to set the cursor
        call win_gotoid(s:winid)
        let l:old_scrolloff = &scrolloff
        let &scrolloff = 0

        call nvim_win_set_cursor(s:winid, [a:options['cursor']['line'], a:options['cursor']['col']])
        call s:align_preview(a:options)

        " Finally, go back to the original window
        call win_gotoid(a:current_window_id)

        let &scrolloff = l:old_scrolloff
    elseif s:use_vim_popup
        " Vim popups
        function! AlignVimPopup(timer) closure abort
            call s:align_preview(a:options)
        endfunction
        call timer_start(0, function('AlignVimPopup'))
    else
        " Preview
        " Don't use 'scrolloff', it might mess up the cursor's position
        let &l:scrolloff = 0
        call cursor(a:options['cursor']['line'], a:options['cursor']['col'])
        call s:align_preview(a:options)
    endif
endfunction

function! s:align_preview(options) abort
    if !has_key(a:options, 'cursor') ||
        \ !has_key(a:options['cursor'], 'align')
        return
    endif

    let l:align = a:options['cursor']['align']

    if s:use_vim_popup
        " Vim popups
        let l:pos = popup_getpos(s:winid)
        let l:below = winline() < winheight(0) / 2
        if l:below
            let l:height = min([l:pos['core_height'], winheight(0) - winline() - 2])
        else
            let l:height = min([l:pos['core_height'], winline() - 3])
        endif
        let l:width = l:pos['core_width']

        let l:options = {
            \ 'minwidth': l:width,
            \ 'maxwidth': l:width,
            \ 'minheight': l:height,
            \ 'maxheight': l:height,
            \ 'pos': l:below ? 'topleft' : 'botleft',
            \ 'line': l:below ? 'cursor+1' : 'cursor-1'
            \ }

        if l:align ==? 'top'
            let l:options['firstline'] = a:options['cursor']['line']
        elseif l:align ==? 'center'
            let l:options['firstline'] = a:options['cursor']['line'] - (l:height - 1) / 2
        elseif l:align ==? 'bottom'
            let l:options['firstline'] = a:options['cursor']['line'] - l:height + 1
        endif

        call popup_setoptions(s:winid, l:options)
        redraw!
    else
        " Preview and Neovim floats
        if l:align ==? 'top'
            normal! zt
        elseif l:align ==? 'center'
            normal! zz
        elseif l:align ==? 'bottom'
            normal! zb
        endif
    endif
endfunction

function! lsp#ui#vim#output#get_size_info() abort
    " Get size information while still having the buffer active
    let l:maxwidth = max(map(getline(1, '$'), 'strdisplaywidth(v:val)'))
    if g:lsp_preview_max_width > 0
      let l:bufferlines = 0
      let l:maxwidth = min([g:lsp_preview_max_width, l:maxwidth])

      " Determine, for each line, how many "virtual" lines it spans, and add
      " these together for all lines in the buffer
      for l:line in getline(1, '$')
        let l:num_lines = str2nr(string(ceil(strdisplaywidth(l:line) * 1.0 / g:lsp_preview_max_width)))
        let l:bufferlines += max([l:num_lines, 1])
      endfor
    else
      let l:bufferlines = line('$')
    endif

    return [l:bufferlines, l:maxwidth]
  return [l:bufferlines, l:maxwidth]
endfunction

function! lsp#ui#vim#output#float_supported() abort
    return s:use_vim_popup || s:use_nvim_float
endfunction

function! lsp#ui#vim#output#preview(server, data, options) abort
    if s:is_cmdwin()
        return
    endif

    if s:winid && type(s:preview_data) ==# type(a:data)
        \ && s:preview_data ==# a:data
        \ && type(g:lsp_preview_doubletap) ==# 3
        \ && len(g:lsp_preview_doubletap) >= 1
        \ && type(g:lsp_preview_doubletap[0]) ==# 2
        \ && index(['i', 's'], mode()[0]) ==# -1
        echo ''
        return call(g:lsp_preview_doubletap[0], [])
    endif
    " Close any previously opened preview window
    if s:use_preview
        pclose
    endif

    let l:current_window_id = win_getid()

    let s:preview_data = a:data
    let l:lines = []
    let l:syntax_lines = []
    let l:ft = lsp#ui#vim#output#append(a:data, l:lines, l:syntax_lines)

    " If the server response is empty content, we don't display anything.
    if empty(l:lines) && empty(l:syntax_lines)
        echo ''
        return
    endif

    let s:winid = s:open_preview(a:data)

    if has_key(a:options, 'filetype')
        let l:ft = a:options['filetype']
    endif

    let l:do_conceal = g:lsp_hover_conceal
    let l:server_info = a:server !=# '' ? lsp#get_server_info(a:server) : {}
    let l:config = get(l:server_info, 'config', {})
    let l:do_conceal = get(l:config, 'hover_conceal', l:do_conceal)

    call setbufvar(winbufnr(s:winid), 'lsp_syntax_highlights', l:syntax_lines)
    call setbufvar(winbufnr(s:winid), 'lsp_do_conceal', l:do_conceal)
    call lsp#ui#vim#output#setcontent(s:winid, l:lines, l:ft)

    let [l:bufferlines, l:maxwidth] = lsp#ui#vim#output#get_size_info()

    if s:use_preview
        " Set statusline
        if has_key(a:options, 'statusline')
            let &l:statusline = a:options['statusline']
        endif

        call s:set_cursor(l:current_window_id, a:options)
    endif

    " Go to the previous window to adjust positioning
    call win_gotoid(l:current_window_id)

    echo ''

    if s:winid && (s:use_vim_popup || s:use_nvim_float)
      if s:use_nvim_float
        " Neovim floats
        call lsp#ui#vim#output#adjust_float_placement(l:bufferlines, l:maxwidth)
        call s:set_cursor(l:current_window_id, a:options)
        call s:add_float_closing_hooks()
      elseif s:use_vim_popup
        " Vim popups
        call s:set_cursor(l:current_window_id, a:options)
      endif
	  doautocmd User lsp_float_opened
    endif

    if !g:lsp_preview_keep_focus
        " set the focus to the preview window
        call win_gotoid(s:winid)
    endif
    return ''
endfunction

function! s:escape_string_for_display(str) abort
    return substitute(substitute(a:str, '\r\n', '\n', 'g'), '\r', '\n', 'g')
endfunction

function! lsp#ui#vim#output#append(data, lines, syntax_lines) abort
    if type(a:data) == type([])
        for l:entry in a:data
            call lsp#ui#vim#output#append(l:entry, a:lines, a:syntax_lines)
        endfor

        return 'markdown'
    elseif type(a:data) ==# type('')
        if !empty(a:data)
            call extend(a:lines, split(s:escape_string_for_display(a:data), "\n", v:true))
        endif

        return 'markdown'
    elseif type(a:data) ==# type({}) && has_key(a:data, 'language')
        if !empty(a:data.value)
            let l:new_lines = split(s:escape_string_for_display(a:data.value), '\n')

            let l:i = 1
            while l:i <= len(l:new_lines)
                call add(a:syntax_lines, { 'line': len(a:lines) + l:i, 'language': a:data.language })
                let l:i += 1
            endwhile

            call extend(a:lines, l:new_lines)
        endif

        return 'markdown'
    elseif type(a:data) ==# type({}) && has_key(a:data, 'kind')
        if !empty(a:data.value)
            call extend(a:lines, split(s:escape_string_for_display(a:data.value), '\n', v:true))
        endif

        return a:data.kind ==? 'plaintext' ? 'text' : a:data.kind
    endif
endfunction

function! s:is_cmdwin() abort
    return getcmdwintype() !=# ''
endfunction
