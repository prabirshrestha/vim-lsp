let s:Window = vital#lsp#import('VS.Vim.Window')

"
" lsp#internal#ui#floatwin#scroll
"
function! lsp#internal#ui#floatwin#scroll(delta) abort
  let l:ctx = {}
  function! l:ctx.callback() abort closure
    for l:winid in s:Window.find({ winid -> s:Window.is_floating(winid) })
      let l:info = s:Window.info(l:winid)
      call s:Window.scroll(l:winid, l:info.topline + a:delta)
    endfor
  endfunction
  call timer_start(0, { -> l:ctx.callback() })
  return "\<Ignore>"
endfunction

