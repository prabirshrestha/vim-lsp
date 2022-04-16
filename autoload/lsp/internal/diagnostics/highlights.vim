" internal state for whether it is enabled or not to avoid multiple subscriptions
let s:enabled = 0
let s:namespace_id = '' " will be set when enabled

let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

if !hlexists('LspErrorHighlight')
    highlight link LspErrorHighlight Error
endif

if !hlexists('LspWarningHighlight')
    highlight link LspWarningHighlight Todo
endif

if !hlexists('LspInformationHighlight')
    highlight link LspInformationHighlight Normal
endif

if !hlexists('LspHintHighlight')
    highlight link LspHintHighlight Normal
endif

function! lsp#internal#diagnostics#highlights#_enable() abort
    " don't even bother registering if the feature is disabled
    if !lsp#utils#_has_highlights() | return | endif
    if !g:lsp_diagnostics_highlights_enabled | return | endif 

    if s:enabled | return | endif
    let s:enabled = 1

    if empty(s:namespace_id)
        if has('nvim')
            let s:namespace_id = nvim_create_namespace('vim_lsp_diagnostics_highlights')
        else
            let s:namespace_id = 'vim_lsp_diagnostics_highlights'
            for l:severity in keys(s:severity_sign_names_mapping)
                let l:hl_group = s:severity_sign_names_mapping[l:severity] . 'Highlight'
                call prop_type_add(s:get_prop_type_name(l:severity),
                    \ {'highlight': l:hl_group, 'combine': v:true, 'priority': lsp#internal#textprop#priority('diagnostics_highlight') })
            endfor
        endif
    endif

    let s:Dispose = lsp#callbag#pipe(
        \ lsp#callbag#merge(
        \   lsp#callbag#pipe(
        \       lsp#stream(),
        \       lsp#callbag#filter({x->has_key(x, 'server') && has_key(x, 'response')
        \       && has_key(x['response'], 'method') && x['response']['method'] ==# '$/vimlsp/lsp_diagnostics_updated'
        \       && !lsp#client#is_error(x['response'])}),
        \       lsp#callbag#map({x->x['response']['params']}),
        \   ),
        \   lsp#callbag#pipe(
        \       lsp#callbag#fromEvent(['InsertEnter', 'InsertLeave']),
        \       lsp#callbag#filter({_->!g:lsp_diagnostics_highlights_insert_mode_enabled}),
        \       lsp#callbag#map({_->{ 'uri': lsp#utils#get_buffer_uri() }}),
        \   ),
        \ ),
        \ lsp#callbag#filter({_->g:lsp_diagnostics_highlights_enabled}),
        \ lsp#callbag#debounceTime(g:lsp_diagnostics_highlights_delay),
        \ lsp#callbag#tap({x->s:clear_highlights(x)}),
        \ lsp#callbag#tap({x->s:set_highlights(x)}),
        \ lsp#callbag#subscribe(),
        \ )
endfunction

function! lsp#internal#diagnostics#highlights#_disable() abort
    if !s:enabled | return | endif
    if exists('s:Dispose')
        call s:Dispose()
        unlet s:Dispose
    endif
    call s:clear_all_highlights()
    let s:enabled = 0
endfunction

function! s:get_prop_type_name(severity) abort
    return s:namespace_id . '_' . get(s:severity_sign_names_mapping, a:severity, 'LspError')
endfunction

function! s:clear_all_highlights() abort
    for l:bufnr in range(1, bufnr('$'))
        if bufexists(l:bufnr) && bufloaded(l:bufnr)
            if has('nvim')
                call nvim_buf_clear_namespace(l:bufnr, s:namespace_id, 0, -1)
            else
                for l:severity in keys(s:severity_sign_names_mapping)
                    try
                        " TODO: need to check for valid range before calling prop_add
                        " See https://github.com/prabirshrestha/vim-lsp/pull/721
                        silent! call prop_remove({
                            \ 'type': s:get_prop_type_name(l:severity),
                            \ 'bufnr': l:bufnr,
                            \ 'all': v:true })
                    catch
                        call lsp#log('diagnostics', 'clear_all_highlights', 'prop_remove', v:exception, v:throwpoint)
                    endtry
                endfor
            endif
        endif
    endfor
endfunction

function! s:clear_highlights(params) abort
    " TODO: optimize by looking at params
    call s:clear_all_highlights()
endfunction

function! s:set_highlights(params) abort
    " TODO: optimize by looking at params
    if !g:lsp_diagnostics_highlights_insert_mode_enabled
        if mode()[0] ==# 'i' | return | endif
    endif

    for l:bufnr in range(1, bufnr('$'))
        if lsp#internal#diagnostics#state#_is_enabled_for_buffer(l:bufnr) && bufexists(l:bufnr) && bufloaded(l:bufnr)
            let l:uri = lsp#utils#get_buffer_uri(l:bufnr)
            for [l:server, l:diagnostics_response] in items(lsp#internal#diagnostics#state#_get_all_diagnostics_grouped_by_server_for_uri(l:uri))
                call s:place_highlights(l:server, l:diagnostics_response, l:bufnr)
            endfor
        endif
    endfor
endfunction

function! s:place_highlights(server, diagnostics_response, bufnr) abort
    " TODO: make diagnostics highlights same across vim and neovim
    for l:item in lsp#utils#iteratable(a:diagnostics_response['params']['diagnostics'])
        let [l:start_line, l:start_col] = lsp#utils#position#lsp_to_vim(a:bufnr, l:item['range']['start'])
        let [l:end_line, l:end_col] = lsp#utils#position#lsp_to_vim(a:bufnr, l:item['range']['end'])
        let l:severity = get(l:item, 'severity', 3)
        let l:hl_group = get(s:severity_sign_names_mapping, l:severity, 'LspError') . 'Highlight'
        if has('nvim')
            for l:line in range(l:start_line, l:end_line)
                if l:line == l:start_line
                    let l:highlight_start_col = l:start_col
                else
                    let l:highlight_start_col = 1
                endif

                if l:line == l:end_line
                    let l:highlight_end_col = l:end_col
                else
                    " neovim treats -1 as end of line, special handle it later
                    " when calling nvim_buf_add_higlight
                    let l:highlight_end_col = -1
                endif

                if l:start_line == l:end_line && l:highlight_start_col == l:highlight_end_col
                    " higlighting same start col and end col on same line
                    " doesn't work so use -1 for start col
                    let l:highlight_start_col -= 1
                    if l:highlight_start_col <= 0
                        let l:highlight_start_col = 1
                    endif
                endif

                call nvim_buf_add_highlight(a:bufnr, s:namespace_id, l:hl_group,
                   \ l:line - 1, l:highlight_start_col - 1, l:highlight_end_col == -1 ? -1 : l:highlight_end_col)
            endfor
        else
            try
                " TODO: need to check for valid range before calling prop_add
                " See https://github.com/prabirshrestha/vim-lsp/pull/721
                silent! call prop_add(l:start_line, l:start_col, {
                    \ 'end_lnum': l:end_line,
                    \ 'end_col': l:end_col,
                    \ 'bufnr': a:bufnr,
                    \ 'type': s:get_prop_type_name(l:severity),
                    \ })
            catch
                call lsp#log('diagnostics', 'place_highlights', 'prop_add', v:exception, v:throwpoint)
            endtry
        endif
    endfor
endfunction
