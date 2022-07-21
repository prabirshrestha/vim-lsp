" vint: -ProhibitUnusedVariable
"
let s:context = {}

function! lsp#ui#vim#completion#_setup() abort
  augroup lsp_ui_vim_completion
    autocmd!
    autocmd CompleteDone * call s:on_complete_done()
  augroup END
endfunction

function! lsp#ui#vim#completion#_disable() abort
  augroup lsp_ui_vim_completion
    autocmd!
  augroup END
endfunction

"
" After CompleteDone, v:complete_item's word has been inserted into the line.
" Yet not inserted commit characters.
"
" below example uses | as cursor position.
"
" 1. `call getbuf|`<C-x><C-o>
" 2. select `getbufline` item.
" 3. Insert commit characters. e.g. `(`
" 4. fire CompleteDone, then the line is `call getbufline|`
" 5. call feedkeys to call `s:on_complete_done_after`
" 6. then the line is `call getbufline(|` in `s:on_complete_done_after`
"
function! s:on_complete_done() abort
  " Sometimes, vim occurs `CompleteDone` unexpectedly.
  " We try to detect it by checking empty completed_item.
  if empty(v:completed_item) || get(v:completed_item, 'word', '') ==# '' && get(v:completed_item, 'abbr', '') ==# ''
    doautocmd <nomodeline> User lsp_complete_done
    return
  endif

  " Try to get managed user_data.
  let l:managed_user_data = lsp#omni#get_managed_user_data_from_completed_item(v:completed_item)

  " Clear managed user_data.
  call lsp#omni#_clear_managed_user_data_map()

  " If managed user_data does not exists, skip it.
  if empty(l:managed_user_data)
    doautocmd <nomodeline> User lsp_complete_done
    return
  endif

  let s:context['done_line'] = getline('.')
  let s:context['completed_item'] = copy(v:completed_item)
  let s:context['done_position'] = lsp#utils#position#vim_to_lsp('%', getpos('.')[1 : 2])
  let s:context['complete_position'] = l:managed_user_data['complete_position']
  let s:context['server_name'] = l:managed_user_data['server_name']
  let s:context['completion_item'] = l:managed_user_data['completion_item']
  let s:context['start_character'] = l:managed_user_data['start_character']
  call feedkeys(printf("\<C-r>=<SNR>%d_on_complete_done_after()\<CR>", s:SID()), 'n')
endfunction

"
" Apply textEdit or insertText(snippet) and additionalTextEdits.
"
function! s:on_complete_done_after() abort
  " Clear message line. feedkeys above leave garbage on message line.
  echo ''

  " Ignore process if the mode() is not insert-mode after feedkeys.
  if mode(1)[0] !=# 'i'
    return ''
  endif

  let l:done_line = s:context['done_line']
  let l:completed_item = s:context['completed_item']
  let l:done_position = s:context['done_position']
  let l:complete_position = s:context['complete_position']
  let l:server_name = s:context['server_name']
  let l:completion_item = s:context['completion_item']
  let l:start_character = s:context['start_character']

  " check the commit characters are <BS> or <C-w>.
  if strlen(getline('.')) < strlen(l:done_line)
    doautocmd <nomodeline> User lsp_complete_done
    return ''
  endif

  " Do nothing if text_edit is disabled.
  if !g:lsp_text_edit_enabled
    doautocmd <nomodeline> User lsp_complete_done
    return ''
  endif

  let l:completion_item = s:resolve_completion_item(l:completion_item, l:server_name)

  " clear completed string if need.
  let l:is_expandable = s:is_expandable(l:done_line, l:done_position, l:complete_position, l:completion_item, l:completed_item)
  if l:is_expandable
    call s:clear_auto_inserted_text(l:done_line, l:done_position, l:complete_position)
  endif

  " apply additionalTextEdits.
  if has_key(l:completion_item, 'additionalTextEdits') && !empty(l:completion_item['additionalTextEdits'])
    call lsp#utils#text_edit#apply_text_edits(lsp#utils#get_buffer_uri(bufnr('%')), l:completion_item['additionalTextEdits'])
  endif

  " snippet or textEdit.
  if l:is_expandable
    " At this timing, the cursor may have been moved by additionalTextEdit, so we use overflow information instead of textEdit itself.
    if type(get(l:completion_item, 'textEdit', v:null)) == type({})
      let l:range = lsp#utils#text_edit#get_range(l:completion_item['textEdit'])
      let l:overflow_before = max([0, l:start_character - l:range['start']['character']])
      let l:overflow_after = max([0, l:range['end']['character'] - l:complete_position['character']])
      let l:text = l:completion_item['textEdit']['newText']
    else
      let l:overflow_before = 0
      let l:overflow_after = 0
      let l:text = s:get_completion_text(l:completion_item)
    endif

    " apply snipept or text_edit
    let l:position = lsp#utils#position#vim_to_lsp('%', getpos('.')[1 : 2])
    let l:range = {
    \   'start': {
    \     'line': l:position['line'],
    \     'character': l:position['character'] - (l:complete_position['character'] - l:start_character) - l:overflow_before,
    \   },
    \   'end': {
    \     'line': l:position['line'],
    \     'character': l:position['character'] + l:overflow_after,
    \   }
    \ }

    if get(l:completion_item, 'insertTextFormat', 1) == 2
      " insert Snippet.
      call lsp#utils#text_edit#apply_text_edits('%', [{ 'range': l:range, 'newText': '' }])
      call cursor(lsp#utils#position#lsp_to_vim('%', l:range['start']))
      if exists('g:lsp_snippet_expand') && len(g:lsp_snippet_expand) > 0
        call g:lsp_snippet_expand[0]({ 'snippet': l:text })
      else
        call s:simple_expand_text(l:text)
      endif
    else
      " apply TextEdit.
      call lsp#utils#text_edit#apply_text_edits('%', [{ 'range': l:range, 'newText': l:text }])

      " The VSCode always apply completion word as snippet.
      " It means we should place cursor to end of new inserted text as snippet does.
      let l:lines = lsp#utils#_split_by_eol(l:text)
      let l:start = l:range.start
      let l:start.line += len(l:lines) - 1
      let l:start.character += strchars(l:lines[-1])
      call cursor(lsp#utils#position#lsp_to_vim('%', l:start))
    endif
  endif

  doautocmd <nomodeline> User lsp_complete_done
  return ''
endfunction

"
" is_expandable
"
function! s:is_expandable(done_line, done_position, complete_position, completion_item, completed_item) abort
  if get(a:completion_item, 'textEdit', v:null) isnot# v:null
    let l:range = lsp#utils#text_edit#get_range(a:completion_item['textEdit'])
    if l:range['start']['line'] != l:range['end']['line']
      return v:true
    endif

    " compute if textEdit will change text.
    let l:completed_before = strcharpart(a:done_line, 0, a:complete_position['character'])
    let l:completed_after = strcharpart(a:done_line, a:done_position['character'], strchars(a:done_line) - a:done_position['character'])
    let l:completed_line = l:completed_before . l:completed_after
    let l:text_edit_before = strcharpart(l:completed_line, 0, l:range['start']['character'])
    let l:text_edit_after = strcharpart(l:completed_line, l:range['end']['character'], strchars(l:completed_line) - l:range['end']['character'])
    return a:done_line !=# l:text_edit_before . s:trim_unmeaning_tabstop(a:completion_item['textEdit']['newText']) . l:text_edit_after
  endif
  return s:get_completion_text(a:completion_item) !=# s:trim_unmeaning_tabstop(a:completed_item['word'])
endfunction

"
" trim_unmeaning_tabstop
"
function! s:trim_unmeaning_tabstop(text) abort
  return substitute(a:text, '\%(\$0\|\${0}\)$', '', 'g')
endfunction

"
" Try `completionItem/resolve` if it possible.
"
function! s:resolve_completion_item(completion_item, server_name) abort
  " server_name is not provided.
  if empty(a:server_name)
    return a:completion_item
  endif

  " check server capabilities.
  let l:capabilities = lsp#get_server_capabilities(a:server_name)
  if !has_key(l:capabilities, 'completionProvider')
        \ || type(l:capabilities['completionProvider']) != v:t_dict
        \ || !has_key(l:capabilities['completionProvider'], 'resolveProvider')
        \ || !l:capabilities['completionProvider']['resolveProvider']
    return a:completion_item
  endif

  let l:ctx = {}
  let l:ctx['response'] = {}
  function! l:ctx['callback'](data) abort
    let l:self['response'] = a:data['response']
  endfunction

  try
    call lsp#send_request(a:server_name, {
          \   'method': 'completionItem/resolve',
          \   'params': a:completion_item,
          \   'sync': 1,
          \   'sync_timeout': g:lsp_completion_resolve_timeout,
          \   'on_notification': function(l:ctx['callback'], [], l:ctx)
          \ })
  catch /.*/
    call lsp#log('s:resolve_completion_item', 'request timeout.')
  endtry

  if empty(l:ctx['response'])
    return a:completion_item
  endif

  if lsp#client#is_error(l:ctx['response'])
    return a:completion_item
  endif

  if empty(l:ctx['response']['result'])
    return a:completion_item
  endif

  return l:ctx['response']['result']
endfunction

"
" Remove additional inserted text
"
" LSP server knows only `complete_position` so we should remove inserted text until complete_position.
"
function! s:clear_auto_inserted_text(done_line, done_position, complete_position) abort
  let l:before = strcharpart(a:done_line, 0, a:complete_position['character'])
  let l:after = strcharpart(a:done_line, a:done_position['character'], (strchars(a:done_line) - a:done_position['character']))
  call setline('.', l:before . l:after)
  call cursor([a:done_position['line'] + 1, strlen(l:before) + 1])
endfunction

"
" Expand text
"
function! s:simple_expand_text(text) abort
  let l:pos = {
        \   'line': line('.') - 1,
        \   'character': lsp#utils#to_char('%', line('.'), col('.'))
        \ }

  " Remove placeholders and get first placeholder position that use to cursor position.
  " e.g. `|getbufline(${1:expr}, ${2:lnum})${0}` to getbufline(|,)
  let l:text = substitute(a:text, '\$\%({[0-9]\+\%(:\(\\.\|[^}]\+\)*\)}\|[0-9]\+\)', '\=substitute(submatch(1), "\\", "", "g")', 'g')
  let l:offset = match(a:text, '\$\%({[0-9]\+\%(:\(\\.\|[^}]\+\)*\)}\|[0-9]\+\)')
  if l:offset == -1
    let l:offset = strchars(l:text)
  endif

  call lsp#utils#text_edit#apply_text_edits(lsp#utils#get_buffer_uri(bufnr('%')), [{
        \   'range': {
        \     'start': l:pos,
        \     'end': l:pos
        \   },
        \   'newText': l:text
        \ }])

  let l:pos = lsp#utils#position#lsp_to_vim('%', {
        \   'line': l:pos['line'],
        \   'character': l:pos['character'] + l:offset
        \ })
  call cursor(l:pos)
endfunction

"
" Get completion text from CompletionItem. Fallback to label when insertText
" is falsy
"
function! s:get_completion_text(completion_item) abort
  let l:text = get(a:completion_item, 'insertText', '')
  if empty(l:text)
    let l:text = a:completion_item['label']
  endif
  return l:text
endfunction

"
" Get script id that uses to call `s:` function in feedkeys.
"
function! s:SID() abort
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction

