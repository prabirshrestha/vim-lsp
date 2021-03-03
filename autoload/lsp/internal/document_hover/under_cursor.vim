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
    let l:ui = get(a:options, 'ui', s:FloatingWindow.is_available() ? 'float' : 'preview')
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

function! s:show_hover(ui, server_name, request, response) abort
    if !has_key(a:response, 'result') || empty(a:response['result']) || 
        \ empty(a:response['result']['contents'])
        call lsp#utils#error('No hover information found in server - ' . a:server_name)
        return
    endif

    echo ''

    if s:FloatingWindow.is_available() && a:ui ==? 'float'
		" show floating window
		call s:show_floating_window(a:server_name, a:request, a:response)
    else
        " FIXME: user preview window
        call lsp#ui#vim#output#preview(a:server_name, a:response['result']['contents'], {'statusline': ' LSP Hover'})
	endif
endfunction

function! s:show_floating_window(server_name, request, response) abort
    call s:close_floating_window(v:true)

    let l:contents = s:get_contents(a:response['result']['contents'])

    " Ignore if contents is empty.
    if empty(l:contents)
        return s:close_floating_window(v:true)
    endif

    " Update contents.
    let l:doc_win = s:get_doc_win()
    call deletebufline(l:doc_win.get_bufnr(), 1, '$')
    call setbufline(l:doc_win.get_bufnr(), 1, lsp#utils#_split_by_eol(join(l:contents, "\n\n")))

    " Calculate layout.
    let l:size = l:doc_win.get_size({
        \   'maxwidth': float2nr(&columns * 0.4),
        \   'maxheight': float2nr(&lines * 0.4),
        \ })
    let l:pos = s:compute_position(l:size)
    if empty(l:pos)
        call s:close_floating_window(v:true)
        return
    endif

   " Show popupmenu and apply markdown syntax.
    call l:doc_win.open({
        \   'row': l:pos[0] + 1,
        \   'col': l:pos[1] + 1,
        \   'width': l:size.width,
        \   'height': l:size.height,
        \   'topline': 1,
        \ })
    call s:Window.do(l:doc_win.get_winid(), { -> s:Markdown.apply() })
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
                    let l:detail = s:MarkupContent.normalize({
                        \ 'langauge': &filetype,
                        \ 'value': a:contents['value']
                        \ })
                    return [l:detail]
                else
                    return [a:contents['value']]
                endif
            elseif has_key(a:contents, 'langauge')
                let l:detail = s:MarkupContent.normalize({
                    \ 'langauge': &filetype,
                    \ 'value': a:contents['value']
                    \ })
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

function! s:close_floating_window(force) abort
    if a:force
        call s:get_doc_win().close()
    endif
endfunction

function! s:get_doc_win() abort
    if exists('s:doc_win')
        return s:doc_win
    endif

	let s:doc_win = s:FloatingWindow.new({
		\   'on_opened': { -> execute('doautocmd <nomodeline> User lsp_float_opened') },
		\   'on_closed': { -> execute('doautocmd <nomodeline> User lsp_float_closed') }
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
    " TODO
    return [1,1]
endfunction
