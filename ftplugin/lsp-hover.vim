if exists('b:did_ftplugin')
    finish
endif
let b:did_ftplugin = 1

setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
setlocal nocursorline nofoldenable

if has('syntax')
    setlocal nospell
endif

let &l:statusline = ' LSP Hover'

let b:undo_ftplugin = 'setlocal pvw< bt< bh< swf< bl< cul< fen<' .
            \ (has('syntax') ? ' spell<' : '')
