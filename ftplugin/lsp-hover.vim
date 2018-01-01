" No usual did_ftplugin header here as we NEED to run this always

setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
setlocal nocursorline nofoldenable

if has('syntax')
    setlocal nospell
endif

let &l:statusline = ' LSP Hover'

let b:undo_ftplugin = 'setlocal pvw< bt< bh< swf< bl< cul< fen<' .
            \ (has('syntax') ? ' spell<' : '') .
            \ ' | unlet! g:markdown_fenced_languages'
