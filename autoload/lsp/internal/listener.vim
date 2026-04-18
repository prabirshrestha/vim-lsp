let s:has_listener = exists('*listener_add')
let s:buf_state = {}

function! lsp#internal#listener#is_enabled() abort
    return s:has_listener
endfunction

function! lsp#internal#listener#start(buf) abort
    if !s:has_listener
        return
    endif
    if has_key(s:buf_state, a:buf)
        return
    endif
    let s:buf_state[a:buf] = {
        \ 'listener_id': listener_add(function('s:on_change'), a:buf),
        \ 'changes': [],
        \ 'lsp_cache': {},
        \ 'lines_cache': {},
        \ 'diff_cache': {},
        \ }
endfunction

function! lsp#internal#listener#stop(buf) abort
    if !has_key(s:buf_state, a:buf)
        return
    endif
    call listener_remove(s:buf_state[a:buf].listener_id)
    call remove(s:buf_state, a:buf)
endfunction

function! lsp#internal#listener#flush(buf) abort
    if !has_key(s:buf_state, a:buf)
        return []
    endif
    let l:state = s:buf_state[a:buf]
    call listener_flush(a:buf)
    let l:tick = getbufvar(a:buf, 'changedtick')
    if !empty(l:state.lsp_cache) && l:state.lsp_cache.tick == l:tick
        return l:state.lsp_cache.changes
    endif
    let l:raw = l:state.changes
    let l:state.changes = []
    if empty(l:raw)
        let l:state.lsp_cache = {'tick': l:tick, 'changes': []}
        return []
    endif
    if len(l:raw) == 1
        let l:c = l:raw[0]
        let l:new_end = l:c.lnum + (l:c.end - l:c.lnum) + l:c.added
        if l:c.lnum < l:new_end
            let l:text = join(getbufline(a:buf, l:c.lnum, l:new_end - 1), "\n") . "\n"
        else
            let l:text = ''
        endif
        let l:lsp_changes = [{
            \ 'range': {
            \   'start': {'line': l:c.lnum - 1, 'character': 0},
            \   'end': {'line': l:c.end - 1, 'character': 0},
            \ },
            \ 'text': l:text,
            \ }]
    else
        " Multiple changes accumulated: line numbers from earlier changes
        " reference intermediate buffer states, but getbufline() reads the
        " final state, so individual ranges would carry wrong text.
        " Send full content instead (always valid per LSP spec).
        let l:lsp_changes = [{'text': join(lsp#utils#buffer#_get_lines(a:buf), "\n")}]
    endif
    let l:state.lsp_cache = {'tick': l:tick, 'changes': l:lsp_changes}
    return l:lsp_changes
endfunction

function! lsp#internal#listener#get_lines_cached(buf) abort
    let l:tick = getbufvar(a:buf, 'changedtick')
    if has_key(s:buf_state, a:buf)
        let l:cache = s:buf_state[a:buf].lines_cache
        if !empty(l:cache) && l:cache.tick == l:tick
            return l:cache.lines
        endif
    endif
    let l:lines = lsp#utils#buffer#_get_lines(a:buf)
    if has_key(s:buf_state, a:buf)
        let s:buf_state[a:buf].lines_cache = {'tick': l:tick, 'lines': l:lines}
    endif
    return l:lines
endfunction

function! lsp#internal#listener#get_diff_cached(buf, old_content) abort
    let l:tick = getbufvar(a:buf, 'changedtick')
    if has_key(s:buf_state, a:buf)
        let l:cache = s:buf_state[a:buf].diff_cache
        if !empty(l:cache) && l:cache.tick == l:tick && l:cache.old is a:old_content
            return l:cache.changes
        endif
    endif
    let l:new_content = lsp#internal#listener#get_lines_cached(a:buf)
    let l:changes = lsp#utils#diff#compute(a:old_content, l:new_content)
    if has_key(s:buf_state, a:buf)
        let s:buf_state[a:buf].diff_cache = {'tick': l:tick, 'old': a:old_content, 'changes': l:changes}
    endif
    return l:changes
endfunction

function! s:on_change(buf, start, end, added, changes) abort
    if !has_key(s:buf_state, a:buf)
        return
    endif
    let l:state = s:buf_state[a:buf]
    for l:change in a:changes
        call add(l:state.changes, {
            \ 'lnum': l:change.lnum,
            \ 'end': l:change.end,
            \ 'added': l:change.added,
            \ })
    endfor
endfunction
