"
" lsp#ui#vim#floatwin#nvim#show
"
function! lsp#ui#vim#floatwin#nvim#show(floatwin) abort
  if lsp#ui#vim#floatwin#nvim#is_showing(a:floatwin)
    call nvim_win_set_config(a:floatwin.nvim_window, s:get_config(a:floatwin))
  else
    let a:floatwin.nvim_window = nvim_open_win(a:floatwin.bufnr, v:false, s:get_config(a:floatwin))
  endif
endfunction

"
" lsp#ui#vim#floatwin#nvim#hide
"
function! lsp#ui#vim#floatwin#nvim#hide(floatwin) abort
  if lsp#ui#vim#floatwin#nvim#is_showing(a:floatwin)
    call nvim_win_close(a:floatwin.nvim_window, v:true)
    let a:floatwin.nvim_window = v:null
  endif
endfunction

"
" lsp#ui#vim#floatwin#nvim#write
"
function! lsp#ui#vim#floatwin#nvim#write(floatwin, lines) abort
  call nvim_buf_set_lines(a:floatwin.bufnr, 0, -1, v:true, a:lines)
endfunction

"
" lsp#ui#vim#floatwin#nvim#enter
"
function! lsp#ui#vim#floatwin#nvim#enter(floatwin) abort
  if lsp#ui#vim#floatwin#nvim#is_showing(a:floatwin)
    execute printf('%swincmd w', win_id2win(lsp#ui#vim#floatwin#nvim#winid(a:floatwin)))
  endif
endfunction

"
" lsp#ui#vim#floatwin#nvim#is_showing
"
function! lsp#ui#vim#floatwin#nvim#is_showing(floatwin) abort
  if !has_key(a:floatwin,'nvim_window') || a:floatwin.nvim_window is v:null
    return v:false
  endif

  try
    return nvim_win_get_number(a:floatwin.nvim_window) != -1
  catch /.*/
    let a:floatwin.nvim_window = v:null
  endtry
  return v:false
endfunction

"
" lsp#ui#vim#floatwin#nvim#winid
"
function! lsp#ui#vim#floatwin#nvim#winid(floatwin) abort
  if lsp#ui#vim#floatwin#nvim#is_showing(a:floatwin)
    return win_getid(nvim_win_get_number(a:floatwin.nvim_window))
  endif
  return -1
endfunction

"
" s:get_config
"
function! s:get_config(floatwin) abort
  return {
        \   'relative': 'editor',
        \   'width': a:floatwin.get_width(a:floatwin.contents),
        \   'height': a:floatwin.get_height(a:floatwin.contents),
        \   'row': a:floatwin.screenpos[0],
        \   'col': a:floatwin.screenpos[1],
        \   'focusable': v:true,
        \   'style': 'minimal'
        \ }
endfunction

