" No usual did_ftplugin header here as we NEED to run this always

if has('patch-8.1.1517') && g:lsp_preview_float && !has('nvim')
  " Can not set buftype or popup_close will fail with 'not a popup window'
  setlocal previewwindow bufhidden=wipe noswapfile nobuflisted
else
  setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
endif
setlocal nocursorline nofoldenable
setlocal nonumber norelativenumber

if has('syntax')
    setlocal nospell
endif

let b:undo_ftplugin = 'setlocal pvw< bt< bh< swf< bl< cul< fen<' .
            \ (has('syntax') ? ' spell<' : '') .
            \ ' number< relativenumber<' .
            \ ' | unlet! g:markdown_fenced_languages'
