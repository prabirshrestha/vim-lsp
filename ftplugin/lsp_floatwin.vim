augroup lsp_floatwin
  " This autocmd for support vim's popup-window.
  autocmd!
  autocmd BufWinEnter * call s:update()
augroup END

" @see lsp#view#floatwin
function! LspFloatwinSyntaxShouldUpdate(bufnr) abort
  if !has_key(b:, 'lsp_floatwin_state')
    return v:true
  endif

  if !b:lsp_floatwin_state.markdown_syntax
    return v:true
  endif

  for [l:mark, l:language] in items(s:get_language_map(s:find_marks(a:bufnr)))
    if !has_key(b:lsp_floatwin_state.fenced_language_syntaxes, l:language) ||
          \ !has_key(b:lsp_floatwin_state.fenced_mark_syntaxes, l:mark)
      return v:true
    endif
  endfor
  return v:false
endfunction

" @see lsp#view#floatwin
function! LspFloatwinSyntaxUpdate()
  call s:update()
endfunction

"
" s:update
"
function! s:update()
  if &filetype !=# 'lsp_floatwin'
    return
  endif

  " initialize state.
  let b:lsp_floatwin_state = get(b:, 'lsp_floatwin_state', {
        \   'markdown_syntax': v:false,
        \   'fenced_language_syntaxes': {},
        \   'fenced_mark_syntaxes': {},
        \ })

  " include markdown syntax.
  if !b:lsp_floatwin_state.markdown_syntax
    let b:lsp_floatwin_state.markdown_syntax = v:true

    call s:clear()
    runtime! syntax/markdown.vim
    syntax include @Markdown syntax/markdown.vim
  endif

  for [l:mark, l:language] in items(s:get_language_map(s:find_marks(bufnr('%'))))
    let l:language_group = printf('@LspMarkdownFenced_%s', s:escape(l:language))

    " include syntax for language.
    if !has_key(b:lsp_floatwin_state.fenced_language_syntaxes, l:language)
      let b:lsp_floatwin_state.fenced_language_syntaxes[l:language] = v:true

      try
        for l:syntax_path in s:find_syntax_path(l:language)
          call s:clear()
          execute printf('syntax include %s %s', l:language_group, l:syntax_path)
        endfor
      catch /.*/
        continue
      endtry
    endif

    " add highlight and conceal for mark.
    if !has_key(b:lsp_floatwin_state.fenced_mark_syntaxes, l:mark)
      let b:lsp_floatwin_state.fenced_mark_syntaxes[l:mark] = v:true

      call s:clear()
      let l:escaped_mark = s:escape(l:mark)
      let l:mark_group = printf('LspMarkdownFencedMark_%s', l:escaped_mark)
      let l:mark_start_group = printf('LspMarkdownFencedMarkStart_%s', l:escaped_mark)
      let l:mark_end_group = printf('LspMarkdownFencedMarkEnd_%s', l:escaped_mark)
      let l:start_mark = printf('^\s*```\s*%s\s*', l:mark)
      let l:end_mark = '\s*```\s*$'
      execute printf('syntax region %s matchgroup=%s start="%s" matchgroup=%s end="%s" containedin=@Markdown contains=%s keepend concealends',
            \   l:mark_group,
            \   l:mark_start_group,
            \   l:start_mark,
            \   l:mark_end_group,
            \   l:end_mark,
            \   l:language_group
            \ )
    endif
  endfor
endfunction

"
" find marks.
" @see autoload/lsp/view/floatwin.vim
"
function! s:find_marks(bufnr) abort
  let l:marks = {}

  " find from buffer contents.
  let l:text = join(getbufvar(a:bufnr, 'lsp_floatwin_lines', []), "\n")
  let l:pos = 0
  while 1
    let l:match = matchlist(l:text, '```\s*\(\w\+\)', l:pos, 1)
    if empty(l:match)
      break
    endif
    let l:marks[l:match[1]] = v:true
    let l:pos = matchend(l:text, '```\s*\(\w\+\)', l:pos, 1)
  endwhile

  return keys(l:marks)
endfunction

"
" get_syntax_map
"
function! s:get_language_map(marks) abort
  let l:language_map = {}

  for l:mark in a:marks

    " resolve from g:markdown_fenced_languages
    for l:config in get(g:, 'markdown_fenced_languages', [])
      " Supports `let g:markdown_fenced_languages = ['sh']`
      if l:config !~# '='
        if l:config ==# l:mark
          let l:language_map[l:mark] = l:mark
          break
        endif

      " Supports `let g:markdown_fenced_languages = ['bash=sh']`
      else
        let l:config = split(l:config, '=')
        if l:config[1] ==# l:mark
          let l:language_map[l:config[1]] = l:config[0]
          break
        endif
      endif
    endfor

    " add as-is if can't resolved.
    if !has_key(l:language_map, l:mark)
      let l:language_map[l:mark] = l:mark
    endif
  endfor

  return l:language_map
endfunction

"
" find syntax path.
"
function! s:find_syntax_path(name) abort
  let l:syntax_paths = []
  for l:rtp in split(&runtimepath, ',')
    let l:syntax_path = printf('%s/syntax/%s.vim', l:rtp, a:name)
    if filereadable(l:syntax_path)
      call add(l:syntax_paths, l:syntax_path)
    endif
  endfor
  return l:syntax_paths
endfunction

"
" s:escape
"
function! s:escape(group)
  let l:group = a:group
  let l:group = substitute(l:group, '\.', '_', '')
  return l:group
endfunction

"
" s:clear
"
function! s:clear()
  let b:current_syntax = ''
  unlet b:current_syntax

  let g:main_syntax = ''
  unlet g:main_syntax
endfunction

