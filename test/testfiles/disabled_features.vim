" Run in a fresh process so no earlier test has autoloaded these modules.
let g:lsp_document_code_action_signs_enabled = 0
let g:lsp_semantic_enabled = 0
let g:lsp_inlay_hints_enabled = 0
let g:lsp_diagnostics_echo_cursor = 0
let g:lsp_diagnostics_virtual_text_enabled = 0
runtime plugin/lsp.vim

let s:features = [
    \ 'lsp#internal#document_code_action#signs',
    \ 'lsp#internal#semantic',
    \ 'lsp#internal#inlay_hints',
    \ 'lsp#internal#diagnostics#echo',
    \ 'lsp#internal#diagnostics#virtual_text',
    \ ]
call lsp#enable()
for s:feature in s:features
    call assert_false(exists('*' . s:feature . '#_enable'), s:feature)
endfor
call lsp#disable()
for s:feature in s:features
    call assert_false(exists('*' . s:feature . '#_enable'), s:feature)
endfor

" Re-enabling must honor the new settings, and disabling must clean up even
" when the settings have already been turned off again.
let g:lsp_document_code_action_signs_enabled = 1
let g:lsp_semantic_enabled = 1
let g:lsp_diagnostics_echo_cursor = 1
let g:lsp_diagnostics_virtual_text_enabled = 1
call lsp#enable()
for s:feature in s:features
    if s:feature !=# 'lsp#internal#inlay_hints'
        call assert_true(exists('*' . s:feature . '#_enable'), s:feature)
    endif
endfor
if lsp#internal#semantic#is_enabled()
    call assert_match('lsp_buffer_enabled', execute('autocmd lsp#internal#semantic'))
endif
let g:lsp_document_code_action_signs_enabled = 0
let g:lsp_semantic_enabled = 0
let g:lsp_diagnostics_echo_cursor = 0
let g:lsp_diagnostics_virtual_text_enabled = 0
call lsp#disable()
call assert_notmatch('lsp_buffer_enabled', execute('autocmd lsp#internal#semantic'))

" Inlay hints can also be enabled after the initial disabled startup.
let g:lsp_inlay_hints_enabled = 1
call lsp#enable()
call assert_true(exists('*lsp#internal#inlay_hints#_enable'))
call lsp#internal#inlay_hints#_disable()
call lsp#disable()
