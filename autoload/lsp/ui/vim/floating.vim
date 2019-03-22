let s:supports_floating = has('nvim') && exists('*nvim_win_set_config')
let s:current_floating = {}
let s:floating = {}

if &background ==# 'dark'
    hi def lspFloatingWindowNormal term=None guifg=#eeeeee guibg=#333333 ctermfg=255 ctermbg=234
    hi def lspFloatingWindowEndOfBuffer term=None guifg=#333333 guibg=#333333 ctermfg=234 ctermbg=234
else
    hi def lspFloatingWindowNormal term=None guibg=#eeeeee guifg=#333333 ctermbg=255 ctermfg=234
    hi def lspFloatingWindowEndOfBuffer term=None guibg=#333333 guifg=#333333 ctermbg=234 ctermfg=234
endif

function! s:on_cursor_moved() abort
    if s:current_floating == {}
        autocmd! plugin-lsp-floating-window-close * <buffer>
        return
    endif

    if s:current_floating.opened_at != getpos('.')
        autocmd! plugin-lsp-floating-window-close * <buffer>
        call s:current_floating.close()
        unlet s:current_floating
        let s:current_floating = {}
        return
    endif
endfunction

function! s:on_window_moved() abort
    if s:current_floating == {}
        autocmd! plugin-lsp-floating-window-close * <buffer>
        return
    endif

    autocmd! plugin-lsp-floating-window-close * <buffer>
    call s:current_floating.close()
    unlet s:current_floating
    let s:current_floating = {}
    return
endfunction

function! s:parse_hover_contents(contents, data) abort
    let l:contents = a:contents
    if type(a:data) == type([])
        " MarkedString[]
        for l:entry in a:data
            let l:tmp_contents = s:parse_hover_contents(l:contents, l:entry)
            let l:contents = l:contents + l:tmp_contents
        endfor
        return l:contents
    elseif type(a:data) == type('')
        " String
        return split(a:data, '\n')
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        " MarkedString
        return split(a:data.value, '\n')
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        " MarkupContent
        return split(a:data.value, '\n')
    endif
endfunction

function! s:floating__window_size() dict abort
    " Note: Unlike col('.'), wincol() considers length of sign column
    let origin = win_screenpos(bufwinnr(self.opener_bufnr))
    let abs_cursor_line = (origin[0] - 1) + self.opened_at[1] - line('w0')
    let abs_cursor_col = (origin[1] - 1) + wincol() - col('w0')

    let width = 0
    let max_width = 100
    let height = 0
    for line in self.contents
        let lw = strdisplaywidth(line)
        if lw > width
            if lw > max_width
                let height += lw / max_width + 1
                let width = max_width
                continue
            endif
            let width = lw
        endif
        let height += 1
    endfor
    let width += 1 " right margin

    return [width, height]
endfunction
let s:floating.window_size = funcref('s:floating__window_size')

function! s:floating__floating_win_opts(width, height) dict abort
    let bottom_line = line('w0') + winheight(0) - 1
    if self.opened_at[1] + a:height <= bottom_line
        let vert = 'N'
        let row = 1
    else
        let vert = 'S'
        let row = 0
    endif

    if self.opened_at[2] + a:width <= &columns
        let hor = 'W'
        let col = 0
    else
        let hor = 'E'
        let col = 1
    endif

    return {
    \   'relative': 'cursor',
    \   'anchor': vert . hor,
    \   'row': row,
    \   'col': col,
    \   'width': a:width,
    \   'height': a:height,
    \ }
endfunction
let s:floating.floating_win_opts = funcref('s:floating__floating_win_opts')

function! s:floating__open() dict abort
    " Collect opener buffer info
    let self.opened_at = getpos('.')
    let self.opener_bufnr = bufnr('%')
    let opener_winnr = winnr()

    " open floating window
    let [width, height] = self.window_size()
    let opts = self.floating_win_opts(width, height)
    let self.win_id = nvim_open_win(self.opener_bufnr, v:true, opts)
    enew!
    let self.bufnr = bufnr('%')

    " Setup contents
    call setline(1, self.contents)
    setlocal
    \ buftype=nofile bufhidden=wipe nomodified nobuflisted noswapfile nonumber
    \ nocursorline wrap nonumber norelativenumber signcolumn=no nofoldenable
    \ nospell nolist nomodeline
    setlocal nomodified nomodifiable
    setlocal winhighlight=Normal:lspFloatingWindowNormal,EndOfBuffer:lspFloatingWindowEndOfBuffer

    " Return opener buffer
    execute opener_winnr . 'wincmd w'

    " Setup auto command for close floating window triggered by cursor move or window move
    augroup plugin-lsp-floating-window-close
        autocmd CursorMoved,CursorMovedI,InsertEnter <buffer> call s:on_cursor_moved()
        autocmd WinLeave <buffer> call s:on_window_moved()
    augroup END
endfunction
let s:floating.open = funcref('s:floating__open')

function! s:floating__get_winnr() dict abort
    if !has_key(self, 'bufnr')
        return -1
    endif

    " Note: bufwinnr() is not available here because there may be multiple
    " windows which open the buffer. This situation happens when enter <C-w>v
    " in floating window. It opens a new normal window with the floating's buffer.
    return win_id2win(self.win_id)
endfunction
let s:floating.get_winnr = funcref('s:floating__get_winnr')

function! s:floating__close() dict abort
    if !has_key(self, 'bufnr')
        " Already closed
        return
    endif

    let winnr = self.get_winnr()
    if winnr > 0
        " Without this 'noautocmd', the BufWipeout event will be triggered and
        " this function will be called again.
        noautocmd execute winnr . 'wincmd c'
    endif

    unlet self.bufnr
    unlet self.win_id
endfunction
let s:floating.close = funcref('s:floating__close')

function! lsp#ui#vim#floating#open(data) abort
    if !s:supports_floating | return | endif

    if s:current_floating != {}
        call s:current_floating.close()
    endif

    let fw = deepcopy(s:floating)
    let contents = s:parse_hover_contents([], a:data)
    let fw.contents = contents
    call fw.open()
    let s:current_floating = fw

    echo ''
endfunction

function! lsp#ui#vim#floating#close() abort
    if !s:supports_floating | return | endif

    if s:current_floating != {}
        call s:current_floating.close()
    endif
endfunction
