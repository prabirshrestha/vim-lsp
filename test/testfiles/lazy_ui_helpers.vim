runtime plugin/lsp.vim
let g:lsp_diagnostics_signs_enabled = 1
let g:lsp_completion_documentation_enabled = 1

function! s:private_function(file, name) abort
    let l:scripts = filter(split(execute('scriptnames'), "\n"),
        \ 'substitute(v:val, "\\\\", "/", "g") =~# a:file . "$"')
    call assert_equal(1, len(l:scripts))
    return function('<SNR>' . matchstr(l:scripts[0], '\d\+') . '_' . a:name)
endfunction

call lsp#internal#diagnostics#signs#_enable()
call lsp#internal#completion#documentation#_enable()
call assert_false(exists('*vital#_lsp#VS#Vim#Buffer#import'))
call assert_false(exists('*vital#_lsp#VS#Vim#Window#FloatingWindow#import'))

" A completion that never displayed documentation must not create a buffer.
let s:Close = s:private_function('completion/documentation.vim', 'close_floating_window')
let s:buffers = len(getbufinfo())
call s:Close(v:true)
sleep 10m
call assert_equal(s:buffers, len(getbufinfo()))
call assert_false(exists('*vital#_lsp#VS#Vim#Buffer#import'))
call assert_false(exists('*vital#_lsp#VS#Vim#Window#FloatingWindow#import'))

if exists('*sign_getplaced')
    call setline(1, ['first', 'second'])
    let s:Place = s:private_function('diagnostics/signs.vim', 'place_signs')
    call s:Place('test', {'params': {'diagnostics': [
        \ {'range': {'start': {'line': 1, 'character': 0}}, 'severity': 1}
        \ ]}}, bufnr('%'))
    let s:signs = sign_getplaced(bufnr('%'), {'group': 'vim_lsp'})[0].signs
    call assert_equal(1, len(s:signs))
    call assert_equal(2, s:signs[0].lnum)
    call assert_equal('LspError', s:signs[0].name)
endif
call lsp#internal#diagnostics#signs#_disable()

if has('nvim') || exists('*popup_create')
    let s:GetWindow = s:private_function('completion/documentation.vim', 'get_doc_win')
    let s:window = s:GetWindow()
    call setbufline(s:window.get_bufnr(), 1, ['documentation'])
    call s:window.open({'row': 1, 'col': 1, 'width': 20, 'height': 2})
    call assert_true(s:window.is_visible())
    call assert_equal(['documentation'], getbufline(s:window.get_bufnr(), 1, '$'))
    call s:Close(v:true)
    sleep 10m
    call assert_false(s:window.is_visible())
    call assert_equal(s:window.get_bufnr(), s:GetWindow().get_bufnr())
endif
call lsp#internal#completion#documentation#_disable()
