function! lsp#utils#text_edit#apply_text_edits(uri, text_edits) abort
    " https://microsoft.github.io/language-server-protocol/specification#textedit
    " The order in the array defines the order in which the inserted string
    " appear in the resulting text.
    "
    " The edits must be applied in the reverse order so the early edits will
    " not interfere with the position of later edits, they need to be applied
    " one at the time or put together as a single command.
    "
    " Example: {"range": {"end": {"character": 45, "line": 5}, "start":
    " {"character": 45, "line": 5}}, "newText": "\n"}, {"range": {"end":
    " {"character": 45, "line": 5}, "start": {"character": 45, "line": 5}},
    " "newText": "import javax.ws.rs.Consumes;"}]}}
    "
    " If we apply the \n first we will need adjust the line range of the next
    " command (so the import will be written on the next line) , but if we
    " write the import first and then the \n everything will be fine.
    " If you do not apply a command one at  time, you will need to adjust the
    " range columns after which edit. You will get this (only one execution):
    "
    " execute 'keepjumps normal! 6G045laimport javax.ws.rs.Consumes;'" |
    " execute 'keepjumps normal! 6G045la\n'
    "
    " resulting in this:
    " import javax.servlet.http.HttpServletRequest;i
    " mport javax.ws.rs.Consumes;
    "
    " instead of this (multiple executions):
    " execute 'keepjumps normal! 6G045laimport javax.ws.rs.Consumes;'"
    " execute 'keepjumps normal! 6G045li\n'
    "
    " resulting in this:
    " import javax.servlet.http.HttpServletRequest;
    " import javax.ws.rs.Consumes;
    "
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
    let l:i = 0

    while l:i < len(l:text_edits)
        let l:merged_text_edit = s:merge_same_range(l:i, l:text_edits)
        let l:cmd = s:build_cmd(a:uri, l:merged_text_edit['merged'])

        try
            let l:was_paste = &paste
            let l:was_selection = &selection
            let l:was_virtualedit = &virtualedit
            let l:was_view = winsaveview()

            set paste

            let l:start_line = l:merged_text_edit['merged']['range']['start']['line']
            let l:end_line = l:merged_text_edit['merged']['range']['end']['line']
            let l:end_character = l:merged_text_edit['merged']['range']['end']['character']
            if l:start_line < l:end_line && l:end_character <= 0
                " set inclusive if end position was newline character.
                set selection=inclusive
            else
                set selection=exclusive
            endif

            set virtualedit=onemore

            silent execute l:cmd
        finally
            let &paste = l:was_paste
            let &selection = l:was_selection
            let &virtualedit = l:was_virtualedit
            call winrestview(l:was_view)
        endtry

        let l:i = l:merged_text_edit['end_index']
    endwhile
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

" https://microsoft.github.io/language-server-protocol/specification#textedit
function! s:is_insert(range) abort
    return a:range['start']['line'] == a:range['end']['line'] &&
        \ a:range['start']['character'] == a:range['end']['character']
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

    return !s:is_insert(a:text_edit1['range']) ? -1 :
        \ s:is_insert(a:text_edit2['range']) ? 0 : 1
endfunction

function! s:build_cmd(uri, text_edit) abort
    let l:path = lsp#utils#uri_to_path(a:uri)
    let l:buffer = bufnr(l:path)
    let l:cmd = 'keepjumps keepalt ' . (l:buffer !=# -1 ? 'b ' . l:buffer : 'edit ' . l:path)
    let s:text_edit = deepcopy(a:text_edit)

    let s:text_edit['range'] = s:parse_range(s:text_edit['range'])
    let l:sub_cmd = s:generate_sub_cmd(s:text_edit)
    let l:escaped_sub_cmd = substitute(l:sub_cmd, '''', '''''', 'g')
    let l:cmd = l:cmd . " | execute 'keepjumps normal! " . l:escaped_sub_cmd . "'"

    call lsp#log('s:build_cmd', l:cmd)

    return l:cmd
endfunction

function! s:generate_sub_cmd(text_edit) abort
    if s:is_insert(a:text_edit['range'])
        return s:generate_sub_cmd_insert(a:text_edit)
    else
        return s:generate_sub_cmd_replace(a:text_edit)
    endif
endfunction

function! s:generate_sub_cmd_insert(text_edit) abort
    let l:start_line = a:text_edit['range']['start']['line']
    let l:start_character = a:text_edit['range']['start']['character']

    let l:sub_cmd = s:preprocess_cmd(a:text_edit['range'])
    let l:sub_cmd .= s:generate_move_start_cmd(l:start_line, l:start_character)

    if l:start_character >= strchars(getline(l:start_line))
        let l:sub_cmd .= "\"=l:merged_text_edit['merged']['newText']\<CR>P"
    else
        let l:sub_cmd .= "\"=l:merged_text_edit['merged']['newText'].'?'\<CR>gPh\"_x"
    endif

    return l:sub_cmd
endfunction

function! s:generate_sub_cmd_replace(text_edit) abort
    let l:start_line = a:text_edit['range']['start']['line']
    let l:start_character = a:text_edit['range']['start']['character']
    let l:end_line = a:text_edit['range']['end']['line']
    let l:end_character = a:text_edit['range']['end']['character']
    let l:new_text = a:text_edit['newText']

    let l:sub_cmd = s:preprocess_cmd(a:text_edit['range'])
    let l:sub_cmd .= s:generate_move_start_cmd(l:start_line, l:start_character) " move to the first position

    " If start and end position are 0, we are selecting a range of lines.
    " Thus, we can use linewise-visual mode, which avoids some inconsistencies
    " when applying text edits.
    if l:start_character == 0 && l:end_character == 0
        let l:sub_cmd .= 'V'
    else
        let l:sub_cmd .= 'v'
    endif

    let l:sub_cmd .= s:generate_move_end_cmd(l:end_line, l:end_character) " move to the last position

    if len(l:new_text) == 0
        let l:sub_cmd .= 'x'
    elseif l:start_character == 0 && l:end_character == 0
        let l:sub_cmd .= "\"=l:merged_text_edit['merged']['newText']\<CR>P"
    else
        let l:sub_cmd .= "\"=l:merged_text_edit['merged']['newText'].'?'\<CR>gph\"_x"
    endif

    return l:sub_cmd
endfunction

function! s:generate_move_start_cmd(line_pos, character_pos) abort
    let l:result = printf('%dG0', a:line_pos) " move the line and set to the cursor at the beginning
    if a:character_pos > 0
        let l:result .= printf('%dl', a:character_pos) " move right until the character
    endif
    return l:result
endfunction

function! s:generate_move_end_cmd(line_pos, character_pos) abort
    let l:result = printf('%dG0', a:line_pos) " move the line and set to the cursor at the beginning
    if a:character_pos > 1
        let l:result .= printf('%dl', a:character_pos) " move right until the character
    elseif a:character_pos == 0
        let l:result = printf('%dG$', a:line_pos - 1) " move most right
    endif
    return l:result
endfunction

function! s:preprocess_cmd(range) abort
    " preprocess by opening the folds, this is needed because the line you are
    " going might have a folding
    let l:preprocess = ''

    if foldlevel(a:range['start']['line']) > 0
        let l:preprocess .= a:range['start']['line']
        let l:preprocess .= 'GzO'
    endif

    if foldlevel(a:range['end']['line']) > 0
        let l:preprocess .= a:range['end']['line']
        let l:preprocess .= 'GzO'
    endif

    return l:preprocess
endfunction

" https://microsoft.github.io/language-server-protocol/specification#text-documents
" Position in a text document expressed as zero-based line and zero-based
" character offset, and since we are using the character as a offset position
" we do not have to fix its position
function! s:parse_range(range) abort
    let s:range = deepcopy(a:range)
    let s:range['start']['line'] =  a:range['start']['line'] + 1
    let s:range['end']['line'] = a:range['end']['line'] + 1

    return s:range
endfunction
