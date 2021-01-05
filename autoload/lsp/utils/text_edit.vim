let s:TextEdit = vital#lsp#import('VS.LSP.TextEdit')

function! lsp#utils#text_edit#apply_text_edits(uri, text_edits) abort
    return s:TextEdit.apply(lsp#utils#uri_to_path(a:uri), deepcopy(a:text_edits))
endfunction


" @summary Use this to convert textedit to vim list that is compatible with
" quickfix and locllist items
" @param uri = DocumentUri
" @param text_edit = TextEdit | TextEdit[]
" @returns []
function! lsp#utils#text_edit#_lsp_to_vim_list(uri, text_edit) abort
    let l:result = []
    let l:cache = {}
    if type(a:text_edit) == type([]) " TextEdit[]
        for l:text_edit in a:text_edit
            let l:vim_loc = s:lsp_text_edit_item_to_vim(a:uri, l:text_edit, l:cache)
            if !empty(l:vim_loc)
                call add(l:result, l:vim_loc)
            endif
        endfor
    else " TextEdit
        let l:vim_loc = s:lsp_text_edit_item_to_vim(a:uri, a:text_edit, l:cache)
        if !empty(l:vim_loc)
            call add(l:result, l:vim_loc)
        endif
    endif
    return l:result
endfunction

" @param uri = DocumentUri
" @param text_edit = TextEdit
" @param cache = {} empty dict
" @returns {
"   'filename',
"   'lnum',
"   'col',
"   'text',
" }
function! s:lsp_text_edit_item_to_vim(uri, text_edit, cache) abort
    if !lsp#utils#is_file_uri(a:uri)
        return v:null
    endif

    let l:path = lsp#utils#uri_to_path(a:uri)
    let l:range = a:text_edit['range']
    let [l:line, l:col] = lsp#utils#position#lsp_to_vim(l:path, l:range['start'])

    let l:index = l:line - 1
    if has_key(a:cache, l:path)
        let l:text = a:cache[l:path][l:index]
    else
        let l:contents = getbufline(l:path, 1, '$')
        if !empty(l:contents)
            let l:text = get(l:contents, l:index, '')
        else
            let l:contents = readfile(l:path)
            let a:cache[l:path] = l:contents
            let l:text = get(l:contents, l:index, '')
        endif
    endif

    return {
        \ 'filename': l:path,
        \ 'lnum': l:line,
        \ 'col': l:col,
        \ 'text': l:text
        \ }
endfunction

