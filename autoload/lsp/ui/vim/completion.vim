let s:context = {}

function! lsp#ui#vim#completion#setup() abort
  augroup lsp_ui_vim_completion
    autocmd!
    autocmd CompleteDone * call s:on_complete_done()
  augroup END
endfunction

"
" After CompleteDone, v:complete_item's word has been inserted into the line.
" Yet not inserted commit characters.
"
" below example uses # as cursor position.
"
" 1. `call getbuf#`<C-x><C-o>
" 2. select `getbufline` item.
" 3. Insert commit characters. e.g. `(`
" 4. fire CompleteDone, then the line is `call getbufline#`
" 5. call feedkeys to call `s:on_complete_done_after`
" 6. then the line is `call getbufline(#` in `s:on_complete_done_after`
"
function! s:on_complete_done() abort
  let l:user_data = lsp#omni#extract_user_data_from_completed_item(v:completed_item)
  if empty(l:user_data)
    doautocmd User lsp_complete_done
    return
  endif

  let s:context.line = getline('.')
  let s:context.position = getpos('.')
  let s:context.completed_item = copy(v:completed_item)
  let s:context.server_name = l:user_data.server_name
  let s:context.completion_item = l:user_data.completion_item
  call feedkeys(printf("\<C-r>=<SNR>%d_on_complete_done_after()\<CR>", s:SID()), 'n')
endfunction

"
" Apply textEdit or insertText(snippet) and additionalTextEdits.
"
function! s:on_complete_done_after() abort
  let l:line = s:context.line
  let l:position = s:context.position
  let l:completed_item = s:context.completed_item
  let l:server_name = s:context.server_name
  let l:completion_item = s:context.completion_item

  " check the commit characters are <BS> or <C-w>.
  if strlen(getline('.')) < strlen(l:line)
    doautocmd User lsp_complete_done
    return ''
  endif

  let l:completion_item = s:resolve_completion_item(l:completion_item, l:server_name)

  " apply textEdit or insertText(snippet).
  let l:expanding_text = s:get_expanding_text(l:completed_item, l:completion_item)
  if strlen(l:expanding_text) > 0
    call s:clear_inserted_text(
          \   l:line,
          \   l:position,
          \   l:completed_item,
          \   l:completion_item
          \ )
  endif

  " apply additionalTextEdits.
  if has_key(l:completion_item, 'additionalTextEdits')
    call lsp#utils#text_edit#apply_text_edits(
          \ lsp#utils#get_buffer_uri(bufnr('%')),
          \ l:completion_item.additionalTextEdits
          \ )
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
        \ || !has_key(l:capabilities.completionProvider, 'resolveProvider')
    return a:completion_item
  endif

  let l:ctx = {}
  let l:ctx.response = {}
  function! l:ctx.callback(data) abort
    let self.response = a:data.response
  endfunction

  call lsp#send_request(a:server_name, {
        \   'method': 'completionItem/resolve',
        \   'params': a:completion_item,
        \   'sync': 1,
        \   'on_notification': function(l:ctx.callback, [], l:ctx)
        \ })

  if empty(l:ctx.response)
    return a:completion_item
  endif

  if lsp#client#is_error(l:ctx.response)
    return a:completion_item
  endif

  return l:ctx.response.result
endfunction

"
" Remove inserted text duratin completion.
"
function! s:clear_inserted_text(line, position, completed_item, completion_item) abort
  " Remove commit characters.
  call setline('.', a:line)

  " Create range to remove v:completed_item.
  let l:range = {
        \   'start': {
        \     'line': a:position[1] - 1,
        \     'character': (a:position[2] + a:position[3]) - strlen(a:completed_item.word) - 1
        \   },
        \   'end': {
        \     'line': a:position[1] - 1,
        \     'character': (a:position[2] + a:position[3]) - 1
        \   }
        \ }

  " Expand remove range to textEdit.
  if has_key(a:completion_item, 'textEdit')
    let l:range.start.character = min([
          \   l:range.start.character,
          \   a:completion_item.textEdit.range.start.character
          \ ])
    let l:range.end.character = max([
          \   l:range.end.character,
          \   a:completion_item.textEdit.range.end.character
          \ ])
  endif

  " Remove.
  call lsp#utils#text_edit#apply_text_edits(lsp#utils#get_buffer_uri(bufnr('%')), [{
        \   'range': l:range,
        \   'newText': ''
        \ }])

  " Move to complete start position.
  call cursor([l:range.start.line + 1, l:range.start.character + 1])
endfunction

"
" Get textEdit.newText or insertText when the text is not same to v:completed_item.word.
"
function! s:get_expanding_text(completed_item, completion_item) abort
  let l:text = a:completed_item.word
  if has_key(a:completion_item, 'textEdit')
    let l:text = a:completion_item.textEdit.newText
  elseif has_key(a:completion_item, 'insertText')
    let l:text = a:completion_item.insertText
  endif
  return l:text != a:completed_item.word ? l:text : ''
endfunction

"
" Get script id that uses to call `s:` function in feedkeys.
"
function! s:SID() abort
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun

