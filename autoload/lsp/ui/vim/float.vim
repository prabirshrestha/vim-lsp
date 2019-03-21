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

let s:float_width = 0  " float window height
let s:float_height = 0

function! s:reset()
	let s:data_buf = []
	call nvim_buf_set_option(s:curbuf, 'modifiable', v:true)
endfunction

function! s:set_buf_option()
	call nvim_buf_set_option(s:curbuf, 'modifiable', v:false)
endfunction

function! s:set_win_option()
	call nvim_win_set_option(s:float_win, 'number', v:false)
	call nvim_win_set_option(s:float_win, 'relativenumber', v:false)
endfunction

function! s:float_win_position() abort
	let l:win_height = winheight('.')
	let l:win_width = winwidth('.')
	let l:max_text_width = l:win_width
	if l:max_text_width > 12
		let l:max_text_width = l:max_text_width - 3
	endif

	let l:max_width = 0
	let l:line_count = 0

	for l:line in s:data_buf
		let l:line_count = l:line_count + 1
		let l:len = strwidth(line)
		if l:len < l:max_text_width
			if l:len > l:max_width
				let l:max_width = l:len
			endif
		else
			let l:max_width = l:max_text_width
			let l:calc_count = l:len / l:max_width
			let l:line_count = l:line_count + l:calc_count
		endif
	endfor

	let l:cline = winline()
	let l:ccol = wincol()

	if l:ccol + l:max_width + 1 <= l:win_width
		let l:ccol = l:ccol - 1
	else
		let l:ccol = l:win_width - l:max_width
	endif

	if l:cline + l:line_count > l:win_height
		if l:cline > l:win_height / 2
			let l:line_count = min([l:line_count, l:cline - 1])
			let l:cline = l:cline - l:line_count - 1
		else
			let l:line_count = l:win_height - l:cline
		endif
	endif

	return {'col': l:ccol, 'row': l:cline, 'height': l:line_count, 'width': l:max_width}

endfunction

function! s:remove_spec_char(data) abort
	return split(a:data, '\%x00')
endfunction

function! lsp#ui#vim#float#float_open(data)
	if s:curbuf ==# 0
		let s:curbuf = nvim_create_buf(v:false, v:true)
	endif
	call s:reset()
	call s:convert_to_data_buf(a:data)
    call nvim_buf_set_lines(s:curbuf, 0, -1, v:true, s:data_buf)
	call s:set_buf_option()
	call s:open_float_win()
endfunction

function! s:convert_to_data_buf(data)
    if type(a:data) == type([])
        for l:entry in a:data
            call s:convert_to_data_buf(entry)
        endfor

        return
    elseif type(a:data) == type('')
		call extend(s:data_buf, s:remove_spec_char(a:data))

        return
    elseif type(a:data) == type({}) && has_key(a:data, 'language')
        call add(s:data_buf, '```'.a:data.language)
        call extend(s:data_buf, s:remove_spec_char(a:data.value))
        call add(s:data_buf, '```')

        return
    elseif type(a:data) == type({}) && has_key(a:data, 'kind')
        call extend(s:data_buf, s:remove_spec_char(a:data.value))

        return
    endif
endfunction

function! s:open_float_win()
	let l:opts = s:float_win_position()
	call extend(l:opts, {'relative': 'win', 'anchor': 'NW'})
    let s:float_win =  nvim_open_win(s:curbuf, v:true, l:opts)
	map <silent> <esc> :call <SID>float_close()<cr>
	call s:set_win_option()
endfunction

function! s:float_close()
	call nvim_win_close(s:float_win, 1)
	unmap <esc>
endfunction
