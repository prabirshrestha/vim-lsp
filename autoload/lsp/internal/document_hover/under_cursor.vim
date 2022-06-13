" https://microsoft.github.io/language-server-protocol/specification#textDocument_hover

let s:Markdown = vital#lsp#import('VS.Vim.Syntax.Markdown')
let s:MarkupContent = vital#lsp#import('VS.LSP.MarkupContent')
let s:FloatingWindow = vital#lsp#import('VS.Vim.Window.FloatingWindow')
let s:Window = vital#lsp#import('VS.Vim.Window')
let s:Buffer = vital#lsp#import('VS.Vim.Buffer')

" options - {
"   server - 'server_name'		" optional
"   ui - 'float' | 'preview'
" }
function! lsp#internal#document_hover#under_cursor#do(options) abort
    let l:bufnr = bufnr('%')
    let l:ui = get(a:options, 'ui', g:lsp_hover_ui)
    if empty(l:ui)
        let l:ui = s:FloatingWindow.is_available() ? 'float' : 'preview'
    endif

    if l:ui ==# 'float'
        let l:doc_win = s:get_doc_win()
        if l:doc_win.is_visible()
            if bufnr('%') ==# l:doc_win.get_bufnr()
                call s:close_floating_window()
            else
                call l:doc_win.enter()
                inoremap <buffer><silent> <Plug>(lsp-float-close) <ESC>:<C-u>call <SID>close_floating_window()<CR>
                nnoremap <buffer><silent> <Plug>(lsp-float-close) :<C-u>call <SID>close_floating_window()<CR>
                execute('doautocmd <nomodeline> User lsp_float_focused')
                if !hasmapto('<Plug>(lsp-float-close)')
                    imap <silent> <buffer> <C-c> <Plug>(lsp-float-close)
                    nmap  <silent> <buffer> <C-c> <Plug>(lsp-float-close)
                endif
            endif
            return
        endif
    endif

    if has_key(a:options, 'server')
        let l:servers = [a:options['server']]
    else
        let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_hover_provider(v:val)')
    endif

    if len(l:servers) == 0
        let l:filetype = getbufvar(l:bufnr, '&filetype')
        call lsp#utils#error('textDocument/hover not supported for ' . l:filetype)
        return
    endif

    redraw | echo 'Retrieving hover ...'

    call lsp#_new_command()

    " TODO: ask user to select server for formatting if there are multiple servers
    let l:request = {
        \ 'method': 'textDocument/hover',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \ },
        \ }
    call lsp#callbag#pipe(
        \ lsp#callbag#fromList(l:servers),
        \ lsp#callbag#flatMap({server->
        \   lsp#request(server, l:request)
        \ }),
        \ lsp#callbag#tap({x->s:show_hover(l:ui, x['server_name'], x['request'], x['response'])}),
        \ lsp#callbag#takeUntil(lsp#callbag#pipe(
        \   lsp#stream(),
        \   lsp#callbag#filter({x->has_key(x, 'command')}),
        \ )),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! lsp#internal#document_hover#under_cursor#getpreviewwinid() abort
    if exists('s:doc_win')
        return s:doc_win.get_winid()
    endif
    return v:null
endfunction

function! s:show_hover(ui, server_name, request, response) abort
    if !has_key(a:response, 'result') || empty(a:response['result']) || 
        \ empty(a:response['result']['contents'])
        call lsp#utils#error('No hover information found in server - ' . a:server_name)
        return
    endif

    echo ''

    if s:FloatingWindow.is_available() && a:ui ==? 'float'
        call s:show_floating_window(a:server_name, a:request, a:response)
    else
        call s:show_preview_window(a:server_name, a:request, a:response)
    endif
endfunction

function! s:show_preview_window(server_name, request, response) abort
    let l:contents = s:get_contents(a:response['result']['contents'])

    " Ignore if contents is empty.
    if empty(l:contents)
        call lsp#utils#error('Empty contents for LspHover')
        return
    endif

    let l:lines = lsp#utils#_split_by_eol(join(l:contents, "\n\n"))
    let l:view = winsaveview()
    let l:alternate=@#
    silent! pclose
    sp LspHoverPreview
    execute 'resize '.min([len(l:lines), &previewheight])
    set previewwindow
    setlocal conceallevel=2
    setlocal bufhidden=hide
    setlocal nobuflisted
    setlocal buftype=nofile
    setlocal noswapfile
    %d _
    call setline(1, l:lines)
    call s:Window.do(win_getid(), {->s:Markdown.apply()})
    execute "normal \<c-w>p"
    call winrestview(l:view)
    let @#=l:alternate
endfunction

function! s:show_floating_window(server_name, request, response) abort
    call s:close_floating_window()

    let l:contents = s:get_contents(a:response['result']['contents'])

    " Ignore if contents is empty.
    if empty(l:contents)
        return s:close_floating_window()
    endif

    " Update contents.
    let l:doc_win = s:get_doc_win()
    silent! call deletebufline(l:doc_win.get_bufnr(), 1, '$')
    call setbufline(l:doc_win.get_bufnr(), 1, lsp#utils#_split_by_eol(join(l:contents, "\n\n")))

    " Calculate layout.
    let l:size = l:doc_win.get_size({
        \   'maxwidth': float2nr(&columns * 0.4),
        \   'maxheight': float2nr(&lines * 0.4),
        \ })
    let l:pos = s:compute_position(l:size)
    if empty(l:pos)
        call s:close_floating_window()
        return
    endif

    execute printf('augroup vim_lsp_hover_close_on_move_%d', bufnr('%'))
        autocmd!
        execute printf('autocmd InsertEnter,BufLeave,CursorMoved <buffer> call s:close_floating_window_on_move(%s)', getcurpos())
    augroup END

   " Show popupmenu and apply markdown syntax.
    call l:doc_win.open({
        \   'row': l:pos[0],
        \   'col': l:pos[1],
        \   'width': l:size.width,
        \   'height': l:size.height,
        \   'border': v:true,
        \ })
    call s:Window.do(l:doc_win.get_winid(), { -> s:Markdown.apply() })

    " Format contents to fit window
    call setbufvar(l:doc_win.get_bufnr(), '&textwidth', l:size.width)
    call s:Window.do(l:doc_win.get_winid(), { -> s:format_window() })
endfunction

function! s:format_window() abort
    global/^/normal! gqgq
endfunction

function! s:get_contents(contents) abort
    if type(a:contents) == type('')
        return [a:contents]
    elseif type(a:contents) == type([])
        let l:result = []
        for l:content in a:contents
            let l:result += s:get_contents(l:content)
        endfor
        return l:result
    elseif type(a:contents) == type({})
        if has_key(a:contents, 'value')
            if has_key(a:contents, 'kind')
                if a:contents['kind'] ==? 'markdown'
                    let l:detail = s:MarkupContent.normalize(a:contents['value'])
                    return [l:detail]
                else
                    return [a:contents['value']]
                endif
            elseif has_key(a:contents, 'language')
                let l:detail = s:MarkupContent.normalize(a:contents)
                return [l:detail]
            else
                return ''
            endif
        else
            return ''
        endif
    else
        return ''
    endif
endfunction

function! s:close_floating_window() abort
    call s:get_doc_win().close()
endfunction

function! s:close_floating_window_on_move(curpos) abort
    if a:curpos != getcurpos() | call s:close_floating_window() | endif
endf

function! s:on_opened() abort
    inoremap <buffer><silent> <Plug>(lsp-float-close) <ESC>:<C-u>call <SID>close_floating_window()<CR>
    nnoremap <buffer><silent> <Plug>(lsp-float-close) :<C-u>call <SID>close_floating_window()<CR>
    execute('doautocmd <nomodeline> User lsp_float_opened')
    if !hasmapto('<Plug>(lsp-float-close)')
        imap <silent> <buffer> <C-c> <Plug>(lsp-float-close)
        nmap  <silent> <buffer> <C-c> <Plug>(lsp-float-close)
    endif
endfunction

function! s:on_closed() abort
    execute('doautocmd <nomodeline> User lsp_float_closed')
endfunction

function! s:get_doc_win() abort
    if exists('s:doc_win')
        return s:doc_win
    endif

    let s:doc_win = s:FloatingWindow.new({
        \   'on_opened': function('s:on_opened'),
        \   'on_closed': function('s:on_closed')
        \ })
    call s:doc_win.set_var('&wrap', 1)
    call s:doc_win.set_var('&conceallevel', 2)
    call s:doc_win.set_bufnr(s:Buffer.create())
    call setbufvar(s:doc_win.get_bufnr(), '&buftype', 'nofile')
    call setbufvar(s:doc_win.get_bufnr(), '&bufhidden', 'hide')
    call setbufvar(s:doc_win.get_bufnr(), '&buflisted', 0)
    call setbufvar(s:doc_win.get_bufnr(), '&swapfile', 0)
    return s:doc_win
endfunction

function! s:compute_position(size) abort
    let l:pos = screenpos(0, line('.'), col('.'))
    if l:pos.row == 0 && l:pos.col == 0
        " When the specified position is not visible
        return []
    endif
    let l:pos = [l:pos.row + 1, l:pos.curscol + 1]
    if l:pos[0] + a:size.height > &lines
        let l:pos[0] = l:pos[0] - a:size.height - 3
    endif
    if l:pos[1] + a:size.width > &columns
        let l:pos[1] = l:pos[1] - a:size.width - 3
    endif
    return l:pos
endfunction

