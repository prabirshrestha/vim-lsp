" Applies WorkspaceEdit changes.
function! lsp#utils#workspace_edit#apply_workspace_edit(workspace_edit) abort
    let l:loclist_items = []

    if has_key(a:workspace_edit, 'documentChanges')
        for l:text_document_edit in a:workspace_edit['documentChanges']
            if has_key(l:text_document_edit, 'textDocument')
                let l:loclist_items += s:_apply(l:text_document_edit['textDocument']['uri'], l:text_document_edit['edits'])
            elseif has_key(l:text_document_edit, 'kind')
                let l:loclist_items += s:_apply_document(l:text_document_edit)
            endif
        endfor
    elseif has_key(a:workspace_edit, 'changes')
        for [l:uri, l:text_edits] in items(a:workspace_edit['changes'])
            let l:loclist_items += s:_apply(l:uri, l:text_edits)
        endfor
    endif

    if g:lsp_show_workspace_edits
        call setloclist(0, l:loclist_items, 'r')
        execute 'lopen'
    endif
endfunction

"
" _apply
"
function! s:_apply(uri, text_edits) abort
    call lsp#utils#text_edit#apply_text_edits(a:uri, a:text_edits)
    return lsp#utils#text_edit#_lsp_to_vim_list(a:uri, a:text_edits)
endfunction

"
" _apply_document
"
function! s:_apply_document(text_document_edits) abort
    call lsp#utils#text_edit#apply_text_document_edits(a:text_document_edits)
    if a:text_document_edits['kind'] == 'create'
        let l:uri = lsp#utils#uri_to_path(a:text_document_edits['uri'])
        return [{
            \   'filename': l:uri,
            \   'lnum': 1,
            \   'col': 1,
            \   'text': l:uri,
            \  }]
    elseif a:text_document_edits['kind'] == 'rename'
        let l:uri = lsp#utils#uri_to_path(a:text_document_edits['newUri'])
        return [{
            \   'filename': l:uri,
            \   'lnum': 1,
            \   'col': 1,
            \   'text': l:uri,
            \  }]
    endif
    return []
endfunction
