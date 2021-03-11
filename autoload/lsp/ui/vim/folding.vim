let s:has_lua = has('nvim-0.4.0') || (has('lua') && has('patch-8.2.0775'))

function! s:init_lua() abort
  lua <<EOF
  function foldexpr(folding_ranges, linenr)
    local foldlevel = 0
    local prefix = ''
    for i, folding_range in pairs(folding_ranges) do
      if type(folding_range) == 'table' and folding_range['startLine'] ~= nil and folding_range['endLine'] ~= nil then
        startline = folding_range['startLine'] + 1
        endline = folding_range['endLine'] + 1

        if startline <= linenr and linenr <= endline then
          foldlevel = foldlevel + 1
        end

        if startline == linenr then
          prefix = '>'
        elseif endline == linenr then
          prefix = '<'
        end
      end
    end
    return (prefix == '') and '=' or (prefix .. tostring(foldlevel))
  end
EOF
  let s:lua = 1
endfunction

if s:has_lua && !exists('s:lua')
  call s:init_lua()
endif

let s:folding_ranges = {}
let s:textprop_name = 'vim-lsp-folding-linenr'

function! s:find_servers() abort
    return filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_folding_range_provider(v:val)')
endfunction

function! lsp#ui#vim#folding#fold(sync) abort
    let l:servers = s:find_servers()

    if len(l:servers) == 0
        call lsp#utils#error('Folding not supported for ' . &filetype)
        return
    endif

    let l:server = l:servers[0]
    call lsp#ui#vim#folding#send_request(l:server, bufnr('%'), a:sync)
endfunction

function! s:set_textprops(buf) abort
    " Use zero-width text properties to act as a sort of "mark" in the buffer.
    " This is used to remember the line numbers at the time the request was
    " sent. We will let Vim handle updating the line numbers when the user
    " inserts or deletes text.

    " Skip if the buffer doesn't exist. This might happen when a buffer is
    " opened and quickly deleted.
    if !bufloaded(a:buf) | return | endif

    " Create text property, if not already defined
    silent! call prop_type_add(s:textprop_name, {'bufnr': a:buf})

    let l:line_count = s:get_line_count_buf(a:buf)

    " First, clear all markers from the previous run
    call prop_remove({'type': s:textprop_name, 'bufnr': a:buf}, 1, l:line_count)

    " Add markers to each line
    let l:i = 1
    while l:i <= l:line_count
        call prop_add(l:i, 1, {'bufnr': a:buf, 'type': s:textprop_name, 'id': l:i})
        let l:i += 1
    endwhile
endfunction

function! s:get_line_count_buf(buf) abort
    if !has('patch-8.1.1967')
        return line('$')
    endif
    let l:winids = win_findbuf(a:buf)
    return empty(l:winids) ? line('$') : line('$', l:winids[0])
endfunction

function! lsp#ui#vim#folding#send_request(server_name, buf, sync) abort
    if !lsp#capabilities#has_folding_range_provider(a:server_name)
        return
    endif

    if !g:lsp_fold_enabled
        call lsp#log('Skip sending fold request: folding was disabled explicitly')
        return
    endif

    if has('textprop')
        call s:set_textprops(a:buf)
    endif

    call lsp#send_request(a:server_name, {
                \ 'method': 'textDocument/foldingRange',
                \ 'params': {
                \   'textDocument': lsp#get_text_document_identifier(a:buf)
                \ },
                \ 'on_notification': function('s:handle_fold_request', [a:server_name]),
                \ 'sync': a:sync,
                \ 'bufnr': a:buf
                \ })
endfunction

function! s:foldexpr(server, buf, linenr) abort
    if g:lsp_use_lua && s:has_lua
      return luaeval('foldexpr(_A.fr, _A.l)', {'fr': s:folding_ranges[a:server][a:buf], 'l': a:linenr })
    endif

    let l:valid_folding_ranges = copy(filter(
          \ s:folding_ranges[a:server][a:buf],
          \ "type(v:val) == type({}) && has_key(v:val, 'startLine') && has_key(v:val, 'endLine')"
          \ ))
    let l:foldings = filter(
          \ l:valid_folding_ranges,
          \ "v:val['startLine'] + 1 <= a:linenr && a:linenr <= v:val['endLine'] + 1"
          \ )
    let l:foldlevel = len(l:foldings)
    if !empty(filter(copy(l:foldings), "v:val['startLine'] + 1 == a:linenr"))
      return '>' . l:foldlevel
    elseif !empty(filter(l:foldings, "v:val['endLine'] + 1 == a:linenr"))
      return '<' . l:foldlevel
    else
      return '='
    endif
endfunction

" Searches for text property of the correct type on the given line.
" Returns the original linenr on success, or -1 if no textprop of the correct
" type is associated with this line.
function! s:get_textprop_line(linenr) abort
    let l:props = filter(prop_list(a:linenr), {idx, prop -> prop['type'] ==# s:textprop_name})

    if empty(l:props)
        return -1
    else
        return l:props[0]['id']
    endif
endfunction

function! lsp#ui#vim#folding#foldexpr() abort
    let l:servers = s:find_servers()

    if len(l:servers) == 0
        return
    endif

    let l:server = l:servers[0]

    if has('textprop')
        " Does the current line have a textprop with original line info?
        let l:textprop_line = s:get_textprop_line(v:lnum)

        if l:textprop_line == -1
            " No information for current line available, so use indent for
            " previous line.
            return '='
        else
            " Info available, use foldexpr as it would be with original line
            " number
            return s:foldexpr(l:server, bufnr('%'), l:textprop_line)
        endif
    else
        return s:foldexpr(l:server, bufnr('%'), v:lnum)
    endif
endfunction

function! lsp#ui#vim#folding#foldtext() abort
    let l:num_lines = v:foldend - v:foldstart + 1
    let l:summary = getline(v:foldstart) . '...'

    " Join all lines in the fold
    let l:combined_lines = ''
    let l:i = v:foldstart
    while l:i <= v:foldend
        let l:combined_lines .= getline(l:i) . ' '
        let l:i += 1
    endwhile

    " Check if we're in a comment
    let l:comment_regex = '\V' . substitute(&l:commentstring, '%s', '\\.\\*', '')
    if l:combined_lines =~? l:comment_regex
        let l:summary = l:combined_lines
    endif

    return l:summary . ' (' . l:num_lines . ' ' . (l:num_lines == 1 ? 'line' : 'lines') . ') '
endfunction

function! s:handle_fold_request(server, data) abort
    if lsp#client#is_error(a:data) || !has_key(a:data, 'response') || !has_key(a:data['response'], 'result')
        return
    endif

    let l:result = a:data['response']['result']

    if type(l:result) != type([])
        return
    endif

    let l:uri = a:data['request']['params']['textDocument']['uri']
    let l:path = lsp#utils#uri_to_path(l:uri)
    let l:bufnr = bufnr(l:path)

    if l:bufnr < 0
        return
    endif

    if !has_key(s:folding_ranges, a:server)
        let s:folding_ranges[a:server] = {}
    endif
    let s:folding_ranges[a:server][l:bufnr] = l:result

    " Set 'foldmethod' back to 'expr', which forces a re-evaluation of
    " 'foldexpr'. Only do this if the user hasn't changed 'foldmethod',
    " and this is the correct buffer.
    for l:winid in win_findbuf(l:bufnr)
        if getwinvar(l:winid, '&foldmethod') ==# 'expr'
            call setwinvar(l:winid, '&foldmethod', 'expr')
        endif
    endfor
endfunction

