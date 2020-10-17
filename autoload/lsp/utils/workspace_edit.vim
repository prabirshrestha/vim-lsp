" Applies WorkspaceEdit changes.
function! lsp#utils#workspace_edit#apply_workspace_edit(workspace_edit) abort
    call setloclist(0, [], 'r')
    if has_key(a:workspace_edit, 'documentChanges')
        for l:text_document_edit in a:workspace_edit['documentChanges']
            call lsp#utils#text_edit#apply_text_edits(l:text_document_edit['textDocument']['uri'], l:text_document_edit['edits'], {'show_edits': 1})
        endfor
    elseif has_key(a:workspace_edit, 'changes')
        for [l:uri, l:text_edits] in items(a:workspace_edit['changes'])
            call lsp#utils#text_edit#apply_text_edits(l:uri, l:text_edits, {'show_edits': 1})
        endfor
    endif
    execute 'lopen'
endfunction
