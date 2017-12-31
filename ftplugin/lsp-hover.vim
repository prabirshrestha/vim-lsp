setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
setlocal nocursorline nofoldenable

if has('syntax')
    setlocal nospell
endif

let &l:statusline = ' LSP Hover'
