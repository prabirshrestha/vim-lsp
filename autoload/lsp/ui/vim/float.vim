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
let s:data_buf = []

function! s:reset()
	let s:data_buf = []
	call nvim_buf_set_option(s:curbuf, 'modifiable', v:true)
endfunction

function! s:remove_spec_char(data) abort
	return substitute(a:data, '\%x00', "", "g")
endfunction

function! lsp#ui#vim#float#float_open(data)
	if s:curbuf ==# 0
		let s:curbuf = nvim_create_buf(v:false, v:true)
	endif
	call s:reset()
	call s:convert_to_data_buf(a:data)
    call nvim_buf_set_lines(s:curbuf, 0, -1, v:true, s:data_buf)
	call nvim_buf_set_option(s:curbuf, 'modifiable', v:false)
	call s:open_float_win()
endfunction

function! s:convert_to_data_buf(data)
    if type(a:data) == type([])
        for l:entry in a:data
            call s:convert_to_data_buf(entry)
        endfor

        return
    elseif type(a:data) == type('')
		call add(s:data_buf, s:remove_spec_char(a:data))

        return
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        call add(s:data_buf, '```'.a:data.language)
        call add(s:data_buf, s:remove_spec_char(a:data.value))
        call add(s:data_buf, '```')

        return
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        call add(s:data_buf, s:remove_spec_char(a:data.value))

        return
    endif
endfunction

function! s:open_float_win()
	let l:ww = winwidth('.') " win width
	let l:fw = l:ww / 2 "float win width
	let l:wh = winheight('.') " win height
	let l:fh = l:wh / 2 " float win height

	let l:cline = winline() " cursor win line
	let l:fline = 0 " float win start line
	if l:cline + l:fh <= l:wh
		let l:fline = l:cline
	else
		let l:fline = l:cline - l:fh - 1
	endif

	let l:ccol = wincol() " cursor win col
	let l:fcol = 0 " float won start col
	if l:ccol + l:fw <= l:ww
		let l:fcol = l:ccol - 1
	else
		let l:fcol = l:ccol - l:fw
	endif

    let l:opts = {'relative': 'win', 'col': l:fcol, 'row': l:fline, 'height': l:fh, 'width': l:fw, 'anchor': 'NW'}
    "let s:float_win =  nvim_open_win(s:curbuf, v:true, l:fw, l:fh, l:opts)
    let s:float_win =  nvim_open_win(s:curbuf, v:true, l:opts)
	map <silent> <esc> :call <SID>float_close()<cr>
endfunction

function! s:float_close()
	call nvim_win_close(s:float_win, 1)
	unmap <esc>
endfunction
