" Applies WorkspaceEdit changes.
function! lsp#utils#workspace_edit#apply_workspace_edit(workspace_edit) abort
    if has_key(a:workspace_edit, 'documentChanges')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for l:text_document_edit in a:workspace_edit['documentChanges']
            call lsp#utils#text_edit#apply_text_edits(l:text_document_edit['textDocument']['uri'], l:text_document_edit['edits'])
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    elseif has_key(a:workspace_edit, 'changes')
        let l:cur_buffer = bufnr('%')
        let l:view = winsaveview()
        for [l:uri, l:text_edits] in items(a:workspace_edit['changes'])
            call lsp#utils#text_edit#apply_text_edits(l:uri, l:text_edits)
        endfor
        if l:cur_buffer !=# bufnr('%')
            execute 'keepjumps keepalt b ' . l:cur_buffer
        endif
        call winrestview(l:view)
    endif
endfunction
