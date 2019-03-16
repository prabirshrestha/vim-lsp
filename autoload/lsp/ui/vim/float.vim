""""""""""""""""""""""""""""""""""""""""""
"    LICENSE: 
"     Author: 
"    Version: 
" CreateTime: 2019-03-16 16:36:16
" LastUpdate: 2019-03-16 16:36:16
"       Desc: float win
""""""""""""""""""""""""""""""""""""""""""

if exists("s:is_load")
	finish
endif
let s:is_load = 1

let s:float_win = 0
let s:curbuf = 0

function! lsp#ui#vim#float#float_open(data)
	if s:curbuf ==# 0
		let s:curbuf = nvim_create_buf(v:false, v:true)
	endif
    call nvim_buf_set_lines(s:curbuf, 0, -1, v:true, a:data)
	call s:open_float_win()
endfunction

function! s:open_float_win()
	let l:ww = winwidth('.') " win width
	let l:fw = l:ww / 2 "float win width
	let l:wh = winheight('.') " win height
	let l:fh = l:wh / 2 " float win height

	let l:cline = winline() " cursor win line
	let l:fline = 0 " float win start line
	if l:cline <= l:fh
		let l:fline = l:cline
	else
		let l:fline = l:cline - l:fh - 1
	endif

	let l:ccol = wincol() " cursor win col
	let l:fcol = 0 " float won start col
	if l:ccol <= l:fw
		let l:fcol = l:ccol
	else
		let l:fcol = l:ccol - l:fw - 1
	endif

    let l:opts = {'relative': 'win', 'col': l:fcol, 'row': l:fline, 'anchor': 'NW'}
    let s:float_win =  nvim_open_win(s:curbuf, v:true, l:fw, l:fh, l:opts)
	map <silent> <esc> :call <SID>float_close()<cr>
endfunction

function! s:float_close()
	call nvim_win_close(s:float_win, 1)
	unmap <esc>
endfunction
