" Global state
let s:last_req_id = 0
let s:pending = {}
let s:use_vim_textprops = has('textprop') && !has('nvim')
let s:prop_id = 11

" Highlight group for references
if !hlexists('lspReference')
    highlight link lspReference CursorColumn
endif

" Convert a LSP range to one or more vim match positions.
" If the range spans over multiple lines, break it down to multiple
" positions, one for each line.
" Return a list of positions.
function! s:range_to_position(bufnr, range) abort
    let l:position = []

    let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim(a:bufnr, a:range['start'])
    let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim(a:bufnr, a:range['end'])
    if l:end_line == l:start_line
        let l:position = [[
        \ l:start_line,
        \ l:start_col,
        \ l:end_col - l:start_col
        \ ]]
    else
        " First line
        let l:position = [[
        \ l:start_line,
        \ l:start_col,
        \ 999
        \ ]]

        " Last line
        call add(l:position, [
        \ l:end_line,
        \ 1,
        \ l:end_col
        \ ])

        " Lines in the middle
        let l:middle_lines = map(
        \ range(l:start_line + 1, l:end_line - 1),
        \ {_, l -> [l, 0, 999]}
        \ )

        call extend(l:position, l:middle_lines)
    endif

    return l:position
endfunction

" Compare two positions
function! s:compare_positions(p1, p2) abort
    let l:line_1 = a:p1[0]
    let l:line_2 = a:p2[0]
    if l:line_1 != l:line_2
        return l:line_1 > l:line_2 ? 1 : -1
    endif
    let l:col_1 = a:p1[1]
    let l:col_2 = a:p2[1]
    return l:col_1 - l:col_2
endfunction

" If the cursor is over a reference, return its index in
" the array. Otherwise, return -1.
function! s:in_reference(reference_list) abort
    let l:line = line('.')
    let l:column = col('.')
    let l:index = 0
    for l:position in a:reference_list
        if l:line == l:position[0] &&
        \  l:column >= l:position[1] &&
        \  l:column < l:position[1] + l:position[2]
            return l:index
        endif
        let l:index += 1
    endfor
    return -1
endfunction

" Handle response from server.
function! s:handle_references(ctx, data) abort
    " Sanity checks
    if !has_key(s:pending, a:ctx['filetype']) ||
    \  !s:pending[a:ctx['filetype']]
        return
    endif
    let s:pending[a:ctx['filetype']] = v:false
    if lsp#client#is_error(a:data['response'])
        return
    end

    " More sanity checks
    if  a:ctx['bufnr'] != bufnr('%') || a:ctx['last_req_id'] != s:last_req_id
        return
    endif

    " Remove existing highlights from the buffer
    call lsp#ui#vim#references#clean_references()

    " Get references from the response
    let l:reference_list = a:data['response']['result']
    if empty(l:reference_list)
        return
    endif

    " Convert references to vim positions
    let l:position_list = []
    for l:reference in l:reference_list
        call extend(l:position_list, s:range_to_position(a:ctx['bufnr'], l:reference['range']))
    endfor
    call sort(l:position_list, function('s:compare_positions'))

    " Ignore response if the cursor is not over a reference anymore
    if s:in_reference(l:position_list) == -1
        " If the cursor has moved: send another request
        if a:ctx['curpos'] != getcurpos()
            call lsp#ui#vim#references#highlight(v:true)
        endif
        return
    endif

    " Store references
    let w:lsp_reference_positions = l:position_list
    let w:lsp_reference_matches = []

    " Apply highlights to the buffer
    if g:lsp_highlight_references_enabled
        let l:bufnr = bufnr()
        call s:init_reference_highlight(l:bufnr)
        if s:use_vim_textprops
            for l:position in l:position_list
                call prop_add(l:position[0], l:position[1],
                \   {'id': s:prop_id,
                \    'bufnr': l:bufnr,
                \    'length': l:position[2],
                \    'type': 'vim-lsp-reference-highlight'})
                call add(w:lsp_reference_matches, l:position[0])
            endfor
        else
            for l:position in l:position_list
                let l:match = matchaddpos('lspReference', [l:position], -5)
                call add(w:lsp_reference_matches, l:match)
            endfor
        endif
    endif
endfunction

function! s:init_reference_highlight(buf) abort
    if !empty(getbufvar(a:buf, 'lsp_did_reference_setup'))
        return
    endif

    if s:use_vim_textprops
        call prop_type_add('vim-lsp-reference-highlight',
        \   {'bufnr': bufnr(),
        \    'highlight': 'lspReference',
        \    'combine': v:true})
    endif

    call setbufvar(a:buf, 'lsp_did_reference_setup', 1)
endfunction

" Highlight references to the symbol under the cursor
function! lsp#ui#vim#references#highlight(force_refresh) abort
    " No need to change the highlights if the cursor has not left
    " the currently highlighted symbol.
    if !a:force_refresh &&
    \  exists('w:lsp_reference_positions') &&
    \  s:in_reference(w:lsp_reference_positions) != -1
        return
    endif

    " A request for this symbol has already been sent
    if has_key(s:pending, &filetype) && s:pending[&filetype]
        return
    endif

    " Check if any server provides document highlight
    let l:capability = 'lsp#capabilities#has_document_highlight_provider(v:val)'
    let l:servers = filter(lsp#get_allowed_servers(), l:capability)

    if len(l:servers) == 0
        return
    endif

    " Send a request
    let s:pending[&filetype] = v:true
    let s:last_req_id += 1
    let l:ctx = {
        \ 'last_req_id': s:last_req_id,
        \ 'curpos': getcurpos(),
        \ 'bufnr': bufnr('%'),
        \ 'filetype': &filetype,
        \ }
    call lsp#send_request(l:servers[0], {
        \ 'method': 'textDocument/documentHighlight',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \ },
        \ 'on_notification': function('s:handle_references', [l:ctx]),
        \ })
endfunction

" Remove all reference highlights from the buffer
function! lsp#ui#vim#references#clean_references() abort
    let s:pending[&filetype] = v:false
    if exists('w:lsp_reference_matches')
        if s:use_vim_textprops
            let l:bufnr = bufnr()
            for l:line in w:lsp_reference_matches
                silent! call prop_remove(
                \   {'id': s:prop_id,
                \    'bufnr': l:bufnr,
                \    'all': v:true}, l:line)
            endfor
        else
            for l:match in w:lsp_reference_matches
                silent! call matchdelete(l:match)
            endfor
        endif
        unlet w:lsp_reference_matches
        unlet w:lsp_reference_positions
    endif
endfunction

" Cyclically move between references by `offset` occurrences.
function! lsp#ui#vim#references#jump(offset) abort
    if !exists('w:lsp_reference_positions')
        echohl WarningMsg
        echom 'References not available'
        echohl None
        return
    endif

    " Get index of reference under cursor
    let l:index = s:in_reference(w:lsp_reference_positions)
    if l:index < 0
        return
    endif

    let l:n = len(w:lsp_reference_positions)
    let l:index += a:offset

    " Show a message when reaching TOP/BOTTOM of the file
    if l:index < 0
        echohl WarningMsg
        echom 'search hit TOP, continuing at BOTTOM'
        echohl None
    elseif l:index >= len(w:lsp_reference_positions)
        echohl WarningMsg
        echom 'search hit BOTTOM, continuing at TOP'
        echohl None
    endif

    " Wrap index
    if l:index < 0 || l:index >= len(w:lsp_reference_positions)
        let l:index = (l:index % l:n + l:n) % l:n
    endif

    " Jump
    let l:target = w:lsp_reference_positions[l:index][0:1]
    normal! m`
    call cursor(l:target[0], l:target[1])
endfunction
