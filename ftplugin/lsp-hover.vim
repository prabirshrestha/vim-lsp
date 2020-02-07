" No usual did_ftplugin header here as we NEED to run this always

if has('patch-8.1.1517') && g:lsp_preview_float && !has('nvim')
  " Can not set buftype or popup_close will fail with 'not a popup window'
  setlocal bufhidden=wipe noswapfile nobuflisted
else
  setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
endif

if has('conceal') && b:lsp_do_conceal
    setlocal conceallevel=2
endif

setlocal nocursorline nofoldenable nonumber norelativenumber

if has('syntax')
    setlocal nospell
endif

let b:undo_ftplugin = 'setlocal pvw< bt< bh< swf< bl< cul< fen<' .
            \ (has('syntax') ? ' spell<' : '') .
            \ ' number< relativenumber<' .
            \ (has('conceal') && b:lsp_do_conceal ? ' conceallevel<' : '') .
            \ ' | unlet! g:markdown_fenced_languages'
