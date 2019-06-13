let s:supports_floating = exists('*nvim_open_win') || has('patch-8.1.1517')
let s:win = v:false

function! lsp#ui#vim#output#closepreview() abort
  if win_getid() == s:win
    " Don't close if window got focus
    return
  endif
  pclose
  let s:win = v:false
  autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
endfunction

function! s:bufwidth() abort
  let width = winwidth(0)
  let numberwidth = max([&numberwidth, strlen(line('$'))+1])
  let numwidth = (&number || &relativenumber)? numberwidth : 0
  let foldwidth = &foldcolumn

  if &signcolumn ==? 'yes'
    let signwidth = 2
  elseif &signcolumn ==? 'auto'
    let signs = execute(printf('sign place buffer=%d', bufnr('')))
    let signs = split(signs, "\n")
    let signwidth = len(signs)>2? 2: 0
  else
    let signwidth = 0
  endif
  return width - numwidth - foldwidth - signwidth
endfunction


function! s:get_float_positioning(height, width) abort
    let l:height = a:height
    let l:width = a:width
    " For a start show it below/above the cursor
    " TODO: add option to configure it 'docked' at the bottom/top/right
    let l:y = winline()
    if l:y + l:height >= winheight(0)
      " Float does not fit
      if l:y - 2 > l:height
        " Fits above
        let l:y = winline() - l:height
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
    " Positioning is not window but screen relative
    let l:opts = {
          \ 'relative': 'win',
          \ 'row': l:y,
          \ 'col': l:col,
          \ 'width': l:width,
          \ 'height': l:height,
          \ }
    return l:opts
endfunction

function! lsp#ui#vim#output#floatingpreview(data) abort
  if has('nvim')
    let l:buf = nvim_create_buf(v:false, v:true)
    call setbufvar(l:buf, '&signcolumn', 'no')

    " Try to get as much pace right-bolow the cursor, but at least 10x10
    let l:width = max([s:bufwidth(), 10])
    let l:height = max([&lines - winline() + 1, 10])

    let l:opts = s:get_float_positioning(l:height, l:width)

    let s:win = nvim_open_win(buf, v:true, l:opts)
    call nvim_win_set_option(s:win, 'winhl', 'Normal:Pmenu,NormalNC:Pmenu')
    call nvim_win_set_option(s:win, 'foldenable', v:false)
    call nvim_win_set_option(s:win, 'wrap', v:true)
    call nvim_win_set_option(s:win, 'statusline', '')
    call nvim_win_set_option(s:win, 'number', v:false)
    call nvim_win_set_option(s:win, 'relativenumber', v:false)
    call nvim_win_set_option(s:win, 'cursorline', v:false)
    " Enable closing the preview with esc, but map only in the scratch buffer
    nmap <buffer><silent> <esc> :pclose<cr>
    return s:win
  else
    return popup_atcursor('...', {
        \  'moved': 'any',
		    \  'border': [1, 1, 1, 1],
		\})
  endif
endfunction

function! s:setcontent(lines, ft) abort
  if s:supports_floating && g:lsp_preview_float && !has('nvim')
    " vim popup
    call setbufline(winbufnr(s:win), 1, a:lines)
    call win_execute(s:win, 'setlocal filetype=' . a:ft . '.lsp-hover')
  else
    " nvim floating
    call setline(1, a:lines)
    setlocal readonly nomodifiable
    let &l:filetype = a:ft . '.lsp-hover'
  endif
endfunction

function! s:adjust_float_placement(bufferlines, maxwidth) abort
    if has('nvim')
      let l:win_config = {}
      let l:height = min([winheight(s:win), a:bufferlines])
      let l:width = min([winwidth(s:win), a:maxwidth])
      let l:win_config = s:get_float_positioning(l:height, l:width)
      call nvim_win_set_config(s:win, l:win_config )
    endif
endfunction

function! s:add_float_closing_hooks() abort
      augroup lsp_float_preview_close
        autocmd! lsp_float_preview_close CursorMoved,CursorMovedI,VimResized *
        autocmd CursorMoved,CursorMovedI,VimResized * call lsp#ui#vim#output#closepreview()
      augroup END
endfunction

function! lsp#ui#vim#output#preview(data) abort
    " Close any previously opened preview window
    pclose

    let l:current_window_id = win_getid()

    if s:supports_floating && g:lsp_preview_float
      let s:win = lsp#ui#vim#output#floatingpreview(a:data)
    else
      execute &previewheight.'new'
      let s:win = win_getid()
    endif

    let l:lines = []
    let l:ft = s:append(a:data, l:lines)
    call s:setcontent(l:lines, l:ft)

    " Get size information while still having the buffer active
    let l:bufferlines = line('$')
    let l:maxwidth = max(map(getline(1, '$'), 'strdisplaywidth(v:val)'))

    if g:lsp_preview_keep_focus
      " restore focus to the previous window
      call win_gotoid(l:current_window_id)
    endif

    echo ''

    if s:supports_floating && s:win && g:lsp_preview_float && has('nvim')
      call s:adjust_float_placement(l:bufferlines, l:maxwidth)
      call s:add_float_closing_hooks()
    endif
    return ''
endfunction

function! s:append(data, lines) abort
    if type(a:data) == type([])
        for l:entry in a:data
            call s:append(entry, a:lines)
        endfor

        return 'markdown'
    elseif type(a:data) == type('')
        call extend(a:lines, split(a:data, "\n"))

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        call add(a:lines, '```'.a:data.language)
        call extend(a:lines, split(a:data.value, '\n'))
        call add(a:lines, '```')

        return 'markdown'
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        call add(a:lines, a:data.value)

        return a:data.kind ==? 'plaintext' ? 'text' : a:data.kind
    endif
endfunction
