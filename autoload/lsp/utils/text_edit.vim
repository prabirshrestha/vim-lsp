function! lsp#utils#text_edit#apply_text_edits(uri, text_edits) abort
    " https://microsoft.github.io/language-server-protocol/specification#textedit
    " The order in the array defines the order in which the inserted string
    " appear in the resulting text.
    "
    " The edits must be applied in the reverse order so the early edits will
    " not interfere with the position of later edits, they need to be applied
    " one at the time or put together as a single command.
    "
    " The sort is also necessary since the LSP specification does not
    " guarantee that text edits are sorted.
    "
    " Example:
    " Initial text:  "abcdef"
    " Edits:
    " ((0, 0), (0, 1), "") - remove first character 'a'
    " ((0, 4), (0, 5), "") - remove fifth character 'e'
    " ((0, 2), (0, 3), "") - remove third character 'c'
    let l:text_edits = sort(deepcopy(a:text_edits), '<SID>sort_text_edit_desc')

    let l:path = lsp#utils#uri_to_path(a:uri)
    let l:bufnr = bufnr(l:path, v:true)
    if !bufloaded(l:path)
        call bufload(l:path)
        call setbufvar(l:bufnr, '&buflisted', v:true)
    else
        let l:bufnr = bufnr(l:path)
    endif

    let l:fixendofline = lsp#utils#buffer#get_fixendofline(l:bufnr)
    let l:total_lines = len(getbufline(l:bufnr, '^', '$'))

    let l:i = 0
    while l:i < len(l:text_edits)
        let l:merged_text_edit = s:merge_same_range(l:i, l:text_edits)
        let l:text_edit = l:merged_text_edit['merged']
        let l:end_index = l:merged_text_edit['end_index']
        let l:lines = split(l:text_edit['newText'], "\n", v:true)

        if l:fixendofline
                    \ && l:lines[-1] ==# ''
                    \ && l:total_lines <= l:text_edit['range']['end']['line']
                    \ && l:text_edit['range']['end']['character'] == 0
            call remove(l:lines, -1)
        endif

        call s:apply_text_edit(l:bufnr, s:parse_range(l:text_edit['range']), l:lines)

        let l:i = l:end_index
    endwhile
endfunction

function! s:apply_text_edit(buf, range, lines) abort
    let l:start_line = get(getbufline(a:buf, a:range['start']['line']), 0, '')
    let l:before_line = strcharpart(l:start_line, 0, a:range['start']['character'] - 1)
    let l:end_line = get(getbufline(a:buf, a:range['end']['line']), 0, '')
    let l:after_line = strcharpart(l:end_line, a:range['end']['character'] - 1, strchars(l:end_line) - (a:range['end']['character'] - 1))

    let l:lines = copy(a:lines)
    let l:lines[0] = l:before_line . l:lines[0]
    let l:lines[-1] = l:lines[-1] . l:after_line

    let l:lines_len = len(l:lines)
    let l:range_len = a:range['end']['line'] - a:range['start']['line']

    let l:i = 0
    while l:i < l:lines_len
        if l:i <= l:range_len
            call setbufline(a:buf, a:range['start']['line'] + l:i, l:lines[l:i])
        else
            call appendbufline(a:buf, a:range['start']['line'] + l:i - 1, l:lines[l:i])
        endif
        let l:i += 1
    endwhile

    if l:lines_len <= l:range_len
        let l:start = a:range['end']['line'] - (l:range_len - l:lines_len)
        let l:end = a:range['end']['line']
        call deletebufline(a:buf, l:start, l:end)
    endif
endfunction

" Merge the edits on the same range so we do not have to reverse the
" text_edits  that are inserts, also from the specification:
" If multiple inserts have the same position, the order in the array
" defines the order in which the inserted strings appear in the
" resulting text
function! s:merge_same_range(start_index, text_edits) abort
    let l:i = a:start_index + 1
    let l:merged = deepcopy(a:text_edits[a:start_index])

    while l:i < len(a:text_edits) &&
        \ s:is_same_range(l:merged['range'], a:text_edits[l:i]['range'])

        let l:merged['newText'] .= a:text_edits[l:i]['newText']
        let l:i += 1
    endwhile

    return {'merged': l:merged, 'end_index': l:i}
endfunction

function! s:is_same_range(range1, range2) abort
    return a:range1['start']['line'] == a:range2['start']['line'] &&
        \ a:range1['end']['line'] == a:range2['end']['line'] &&
        \ a:range1['start']['character'] == a:range2['start']['character'] &&
        \ a:range1['end']['character'] == a:range2['end']['character']
endfunction

" Compares two text edits, based on the starting position of the range.
" Assumes that edits have non-overlapping ranges.
"
" `text_edit1` and `text_edit2` are dictionaries and represent LSP TextEdit type.
"
" Returns 0 if both text edits starts at the same position (insert text),
" positive value if `text_edit1` starts before `text_edit2` and negative value
" otherwise.
function! s:sort_text_edit_desc(text_edit1, text_edit2) abort
    if a:text_edit1['range']['start']['line'] != a:text_edit2['range']['start']['line']
        return a:text_edit2['range']['start']['line'] - a:text_edit1['range']['start']['line']
    endif

    if a:text_edit1['range']['start']['character'] != a:text_edit2['range']['start']['character']
        return a:text_edit2['range']['start']['character'] - a:text_edit1['range']['start']['character']
    endif

    return 0
endfunction

" https://microsoft.github.io/language-server-protocol/specification#text-documents
" Position in a text document expressed as zero-based line and zero-based
" character offset, and since we are using the character as a offset position
" we do not have to fix its position
function! s:parse_range(range) abort
    let s:range = deepcopy(a:range)
    let s:range['start']['line'] =  a:range['start']['line'] + 1
    let s:range['end']['line'] = a:range['end']['line'] + 1
    let s:range['start']['character'] =  a:range['start']['character'] + 1
    let s:range['end']['character'] = a:range['end']['character'] + 1
    return s:range
endfunction
