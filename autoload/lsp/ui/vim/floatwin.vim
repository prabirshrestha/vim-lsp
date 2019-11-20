let s:floatwin_id = 0

let s:namespace = has('nvim') ? 'nvim' : 'vim'

"
" lsp#ui#vim#floatwin#screenpos
"
function! lsp#ui#vim#floatwin#screenpos(line, col) abort
  let l:pos = getpos('.')
  let l:scroll_x = (l:pos[2] + l:pos[3]) - wincol()
  let l:scroll_y = l:pos[1] - winline()
  let l:winpos = win_screenpos(win_getid())
  return [l:winpos[0] + (a:line - l:scroll_y) - 1, l:winpos[1] + (a:col - l:scroll_x) - 1]
endfunction

"
" lsp#ui#vim#floatwin#import
"
function! lsp#ui#vim#floatwin#import() abort
  return s:Floatwin
endfunction

let s:Floatwin = {}

"
" new
"
function! s:Floatwin.new(option) abort
  let s:floatwin_id += 1
  let l:bufname = printf('lsp_floatwin-%s.lsp_floatwin', s:floatwin_id)
  let l:bufnr = bufnr(l:bufname, v:true)
  call setbufvar(l:bufnr, '&buflisted', 0)
  call setbufvar(l:bufnr, '&buftype', 'nofile')
  call setbufvar(l:bufnr, '&filetype', 'lsp_floatwin')
  return extend(deepcopy(s:Floatwin), {
        \   'id': s:floatwin_id,
        \   'bufnr': l:bufnr,
        \   'max_width': get(a:option, 'max_width', g:lsp_preview_max_width),
        \   'max_height': get(a:option, 'max_height', g:lsp_preview_max_height),
        \   'close_on': get(a:option, 'close_on', []),
        \   'screenpos': [0, 0],
        \   'contents': []
        \ })
endfunction

"
" show_tooltip
"
function! s:Floatwin.show_tooltip(screenpos, contents) abort
  let l:width = self.get_width(a:contents)
  let l:height = self.get_height(a:contents)

  let l:screenpos = copy(a:screenpos)
  let l:screenpos[0] -= 1
  let l:screenpos[1] -= 1

  " fix height.
  if l:screenpos[0] - l:height >= 0
    let l:screenpos[0] -= l:height
  else
    let l:screenpos[0] += 1
  endif

  " fix width.
  if &columns < l:screenpos[1] + l:width
    let l:screenpos[1] -= l:screenpos[1] + l:width - &columns
  endif

  call self.show(l:screenpos,  a:contents)
endfunction

"
" show
"
function! s:Floatwin.show(screenpos, contents) abort
  let self.screenpos = a:screenpos
  let self.contents = a:contents

  " create lines.
  let l:lines = []
  for l:content in a:contents
    let l:lines += l:content
  endfor

  " update bufvars.
  call setbufvar(self.bufnr, 'lsp_floatwin_lines', l:lines)

  " show or move
  call lsp#ui#vim#floatwin#{s:namespace}#show(self)
  call setwinvar(self.winid(), '&wrap', 1)
  if g:lsp_hover_conceal
    call setwinvar(self.winid(), '&conceallevel', 3)
  endif

  " write lines
  call lsp#ui#vim#floatwin#{s:namespace}#write(self, l:lines)

  " update syntax highlight.
  if has('nvim') && LspFloatwinSyntaxShouldUpdate(self.bufnr)
    call lsp#utils#windo(self.winid(), { -> LspFloatwinSyntaxUpdate() })
  endif

  call self.set_close_events()
endfunction

"
" hide
"
function! s:Floatwin.hide() abort
  augroup printf('lsp#ui#vim#floatwin#hide_%s', self.id)
    autocmd!
  augroup END
  call lsp#ui#vim#floatwin#{s:namespace}#hide(self)
endfunction

"
" enter
"
function! s:Floatwin.enter() abort
  if g:lsp_preview_doubletap
    call lsp#ui#vim#floatwin#{s:namespace}#enter(self)
  endif
endfunction

"
" is_showing
"
function! s:Floatwin.is_showing() abort
  return lsp#ui#vim#floatwin#{s:namespace}#is_showing(self)
endfunction

"
" winid
"
function! s:Floatwin.winid() abort
  return lsp#ui#vim#floatwin#{s:namespace}#winid(self)
endfunction

"
" set_close_events
"
function! s:Floatwin.set_close_events() abort
  let l:close_fn = printf('lsp_floatwin_close_%s', self.id)
  let b:[l:close_fn] = { -> self.hide() }

  if g:lsp_preview_autoclose
    augroup printf('lsp#ui#vim#floatwin#hide_%s', self.id)
      autocmd!
      for l:event in self.close_on
        execute printf('autocmd %s <buffer> call b:%s()', l:event, l:close_fn)
      endfor
    augroup END
  endif
endfunction

"
" get_width
"
function! s:Floatwin.get_width(contents) abort
  let l:width = 0
  for l:content in a:contents
    let l:width = max([l:width] + map(copy(l:content), { k, v -> strdisplaywidth(v) }))
  endfor

  if self.max_width != -1
    return max([min([self.max_width, l:width]), 1])
  endif
  return max([l:width, 1])
endfunction

"
" get_height
"
function! s:Floatwin.get_height(contents) abort
  let l:width = self.get_width(a:contents)

  let l:height = len(a:contents) - 1
  for l:content in a:contents
    for l:line in l:content
      let l:height += max([1, float2nr(ceil(strdisplaywidth(l:line) / str2float('' . l:width)))])
    endfor
  endfor

  if self.max_height != -1
    return max([min([self.max_height, l:height]), 1])
  endif
  return max([l:height, 1])
endfunction

