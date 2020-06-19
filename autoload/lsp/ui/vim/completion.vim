" vint: -ProhibitUnusedVariable
"
let s:context = {}

function! lsp#ui#vim#completion#_setup() abort
  augroup lsp_ui_vim_completion
    autocmd!
    autocmd CompleteDone * call s:on_complete_done()
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
  " Somtimes, vim occurs `CompleteDone` unexpectedly.
  " We try to detect it by checking empty completed_item.
  if empty(v:completed_item) || get(v:completed_item, 'word', '') ==# '' && get(v:completed_item, 'abbr', '') ==# ''
    doautocmd User lsp_complete_done
    return
  endif

  " Try to get managed user_data.
  let l:managed_user_data = lsp#omni#get_managed_user_data_from_completed_item(v:completed_item)

  " Clear managed user_data.
  call lsp#omni#_clear_managed_user_data_map()

  " If managed user_data does not exists, skip it.
  if empty(l:managed_user_data)
    doautocmd User lsp_complete_done
    return
  endif

  let s:context['line'] = getline('.')
  let s:context['completed_item'] = copy(v:completed_item)
  let s:context['done_position'] = getpos('.')
  let s:context['complete_position'] = l:managed_user_data['complete_position']
  let s:context['server_name'] = l:managed_user_data['server_name']
  let s:context['completion_item'] = l:managed_user_data['completion_item']
  call feedkeys(printf("\<C-r>=<SNR>%d_on_complete_done_after()\<CR>", s:SID()), 'n')
endfunction

"
" Apply textEdit or insertText(snippet) and additionalTextEdits.
"
function! s:on_complete_done_after() abort
  " Clear message line. feedkeys above leave garbage on message line.
  echo ''

  let l:line = s:context['line']
  let l:completed_item = s:context['completed_item']
  let l:done_position = s:context['done_position']
  let l:complete_position = s:context['complete_position']
  let l:server_name = s:context['server_name']
  let l:completion_item = s:context['completion_item']

  " check the commit characters are <BS> or <C-w>.
  if strlen(getline('.')) < strlen(l:line)
    doautocmd User lsp_complete_done
    return ''
  endif

  " Do nothing if text_edit is disabled.
  if !g:lsp_text_edit_enabled
    doautocmd User lsp_complete_done
    return ''
  endif

  let l:completion_item = s:resolve_completion_item(l:completion_item, l:server_name)

  " clear completed string if need.
  let l:expand_text = s:get_expand_text(l:completed_item, l:completion_item)
  if strlen(l:expand_text) > 0
    call s:clear_inserted_text(
          \   l:line,
          \   l:done_position,
          \   l:complete_position,
          \   l:completed_item,
          \   l:completion_item,
          \ )
  endif

  " apply additionalTextEdits.
  if has_key(l:completion_item, 'additionalTextEdits') && !empty(l:completion_item['additionalTextEdits'])
    call lsp#utils#text_edit#apply_text_edits(
          \ lsp#utils#get_buffer_uri(bufnr('%')),
          \ l:completion_item['additionalTextEdits']
          \ )
  endif

  " expand textEdit or insertText.
  if strlen(l:expand_text) > 0
    if exists('g:lsp_snippet_expand') && len(g:lsp_snippet_expand) > 0
      " other snippet integartion point.
      call g:lsp_snippet_expand[0]({
            \   'snippet': l:expand_text
            \ })
    else
      " expand text simply.
      call s:simple_expand_text(l:expand_text)
    endif
  endif

  doautocmd User lsp_complete_done
  return ''
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
" Remove inserted text during completion.
"
function! s:clear_inserted_text(line, done_position, complete_position, completed_item, completion_item) abort
  " Remove commit characters.
  call setline('.', a:line)

  " Create range to remove v:completed_item.
  let l:range = {
        \   'start': {
        \     'line': a:done_position[1] - 1,
        \     'character': lsp#utils#to_char('%', a:done_position[1], a:done_position[2] + a:done_position[3]) - strchars(a:completed_item['word'])
        \   },
        \   'end': {
        \     'line': a:done_position[1] - 1,
        \     'character': lsp#utils#to_char('%', a:done_position[1], a:done_position[2] + a:done_position[3])
        \   }
        \ }

  " Expand remove range to textEdit.
  if has_key(a:completion_item, 'textEdit')
    let l:range = {
    \   'start': {
    \     'line': a:completion_item['textEdit']['range']['start']['line'],
    \     'character': a:completion_item['textEdit']['range']['start']['character'],
    \   },
    \   'end': {
    \     'line': a:completion_item['textEdit']['range']['end']['line'],
    \     'character': a:completion_item['textEdit']['range']['end']['character'] + strchars(a:completed_item['word']) - (a:complete_position['character'] - l:range['start']['character'])
    \   }
    \ }
  endif

  " Remove v:completed_item.word (and textEdit range if need).
  call lsp#utils#text_edit#apply_text_edits(lsp#utils#get_buffer_uri(bufnr('%')), [{
        \   'range': l:range,
        \   'newText': ''
        \ }])

  " Move to complete start position.
  call cursor(lsp#utils#position#lsp_to_vim('%', l:range['start']))
endfunction

"
" Get textEdit.newText or insertText when the text is not same to v:completed_item.word.
"
function! s:get_expand_text(completed_item, completion_item) abort
  let l:text = a:completed_item['word']
  if has_key(a:completion_item, 'textEdit') && type(a:completion_item['textEdit']) == v:t_dict
    let l:text = a:completion_item['textEdit']['newText']
  elseif has_key(a:completion_item, 'insertText')
    let l:text = a:completion_item['insertText']
  endif
  return l:text != a:completed_item['word'] ? l:text : ''
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
" Get script id that uses to call `s:` function in feedkeys.
"
function! s:SID() abort
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction

