" https://github.com/prabirshrestha/callbag.vim#82f96a7d97342fbf0286e6578b65a60f2bc1ce33
"    :CallbagEmbed path=autoload/lsp/callbag.vim namespace=lsp#callbag

let s:undefined_token = '__callbag_undefined__'
let s:str_type = type('')

function! lsp#callbag#undefined() abort
    return s:undefined_token
endfunction

function! lsp#callbag#isUndefined(d) abort
    return type(a:d) == s:str_type && a:d ==# s:undefined_token
endfunction

function! s:noop(...) abort
endfunction

function! s:createArrayWithSize(size, defaultValue) abort
    let l:i = 0
    let l:array = []
    while l:i < a:size
        call add(l:array, a:defaultValue)
        let l:i = l:i + 1
    endwhile
    return l:array
endfunction

" pipe() {{{
function! lsp#callbag#pipe(...) abort
    let l:Res = a:1
    let l:i = 1
    while l:i < a:0
        let l:Res = a:000[l:i](l:Res)
        let l:i = l:i + 1
    endwhile
    return l:Res
endfunction
" }}}

" operate() {{{
function! lsp#callbag#operate(...) abort
    let l:data = { 'cbs': a:000 }
    return function('s:operateFactory', [l:data])
endfunction

function! s:operateFactory(data, src) abort
    let l:Res = a:src
    let l:n = len(a:data['cbs'])
    let l:i = 0
    while l:i < l:n
        let l:Res = a:data['cbs'][l:i](l:Res)
        let l:i = l:i + 1
    endwhile
    return l:Res
endfunction
" }}}

" makeSubject() {{{
function! lsp#callbag#makeSubject() abort
    let l:data = { 'sinks': [] }
    return function('s:makeSubjectFactory', [l:data])
endfunction

function! s:makeSubjectFactory(data, t, d) abort
    if a:t == 0
        let l:Sink = a:d
        call add(a:data['sinks'], l:Sink)
        call l:Sink(0, function('s:makeSubjectSinkCallback', [a:data, l:Sink]))
    else
        let l:zinkz = copy(a:data['sinks'])
        let l:i = 0
        let l:n = len(l:zinkz)
        while l:i < l:n
            let l:Sink = l:zinkz[l:i]
            let l:j = -1
            let l:found = 0
            for l:Item in a:data['sinks']
                let l:j += 1
                if l:Item == l:Sink
                    let l:found = 1
                    break
                endif
            endfor

            if l:found
                call l:Sink(a:t, a:d)
            endif
            let l:i += 1
        endwhile
    endif
endfunction

function! s:makeSubjectSinkCallback(data, Sink, t, d) abort
    if a:t == 2
        let l:i = -1
        let l:found = 0
        for l:Item in a:data['sinks']
            let l:i += 1
            if l:Item == a:Sink
                let l:found = 1
                break
            endif
        endfor
        if l:found
            call remove(a:data['sinks'], l:i)
        endif
    endif
endfunction
" }}}

" create() {{{
function! lsp#callbag#create(...) abort
    let l:data = {}
    if a:0 > 0
        let l:data['prod'] = a:1
    endif
    return function('s:createProd', [l:data])
endfunction

function! s:createProd(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    if !has_key(a:data, 'prod') || type(a:data['prod']) != type(function('s:noop'))
        call a:sink(0, function('s:noop'))
        call a:sink(2, lsp#callbag#undefined())
        return
    endif
    let a:data['end'] = 0
    call a:sink(0, function('s:createSinkCallback', [a:data]))
    if a:data['end'] | return | endif
    let a:data['clean'] = a:data['prod'](function('s:createNext', [a:data]), function('s:createError', [a:data]), function('s:createComplete', [a:data]))
endfunction

function! s:createSinkCallback(data, t, ...) abort
    if !a:data['end']
        let a:data['end'] = (a:t == 2)
        if a:data['end'] && has_key(a:data, 'clean') && type(a:data['clean']) == type(function('s:noop'))
            call a:data['clean']()
        endif
    endif
endfunction

function! s:createNext(data, d) abort
    if !a:data['end'] | call a:data['sink'](1, a:d) | endif
endfunction

function! s:createError(data, e) abort
    if !a:data['end'] && !lsp#callbag#isUndefined(a:e)
        let a:data['end'] = 1
        call a:data['sink'](2, a:e)
    endif
endfunction

function! s:createComplete(data) abort
    if !a:data['end']
        let a:data['end'] = 1
        call a:data['sink'](2, lsp#callbag#undefined())
    endif
endfunction
" }}}

" lazy() {{{
function! lsp#callbag#lazy(F) abort
    let l:data = { 'F': a:F }
    return function('s:lazyFactory', [l:data])
endfunction

function! s:lazyFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['unsubed'] = 0
    call a:data['sink'](0, function('s:lazySinkCallback', [a:data]))
    call a:data['sink'](1, a:data['F']())
    if !a:data['unsubed'] | call a:data['sink'](2, lsp#callbag#undefined()) | endif
endfunction

function! s:lazySinkCallback(data, t, d) abort
    if a:t == 2 | let a:data['unsubed'] = 1 | endif
endfunction
" }}}

" empty() {{{
function! lsp#callbag#empty() abort
    let l:data = {}
    return function('s:emptyStart', [l:data])
endfunction

function! s:emptyStart(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['disposed'] = 0
    call a:sink(0, function('s:emptySinkCallback', [a:data]))
    if a:data['disposed'] | return | endif
    call a:sink(2, lsp#callbag#undefined())
endfunction

function! s:emptySinkCallback(data, t, ...) abort
    if a:t != 2 | return | endif
    let a:data['disposed'] = 1
endfunction

function! s:empty_sink_callback(data, t, ...) abort
    if a:t == 2 | call timer_stop(a:data['timer']) | endif
endfunction
" }}}

" never() {{{
function! lsp#callbag#never() abort
    return function('s:never')
endfunction

function! s:never(start, sink) abort
    if a:start != 0 | return | endif
    call a:sink(0, function('s:noop'))
endfunction
" }}}

" forEach() {{{
function! lsp#callbag#forEach(operation) abort
    let l:data = { 'operation': a:operation }
    return function('s:forEachOperation', [l:data])
endfunction

function! s:forEachOperation(data, source) abort
    return a:source(0, function('s:forEachOperationSource', [a:data]))
endfunction

function! s:forEachOperationSource(data, t, d) abort
    if a:t == 0 | let a:data['talkback'] = a:d | endif
    if a:t == 1 | call a:data['operation'](a:d) | endif
    if (a:t == 1 || a:t == 0) | call a:data['talkback'](1, lsp#callbag#undefined()) | endif
endfunction
" }}}

" tap() {{{
function! lsp#callbag#tap(...) abort
    let l:data = {}
    if a:0 > 0 && type(a:1) == type({}) " a:1 { next, error, complete }
        if has_key(a:1, 'next') | let l:data['next'] = a:1['next'] | endif
        if has_key(a:1, 'error') | let l:data['error'] = a:1['error'] | endif
        if has_key(a:1, 'complete') | let l:data['complete'] = a:1['complete'] | endif
    else " a:1 = next, a:2 = error, a:3 = complete
        if a:0 >= 1 | let l:data['next'] = a:1 | endif
        if a:0 >= 2 | let l:data['error'] = a:2 | endif
        if a:0 >= 3 | let l:data['complete'] = a:3 | endif
    endif
    return function('s:tapFactory', [l:data])
endfunction

function! s:tapFactory(data, source) abort
    let a:data['source'] = a:source
    return function('s:tapSouceFactory', [a:data])
endfunction

function! s:tapSouceFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:tapSourceCallback', [a:data]))
endfunction

function! s:tapSourceCallback(data, t, d) abort
    if a:t == 1 && has_key(a:data, 'next') | call a:data['next'](a:d) | endif
    if a:t == 2 && lsp#callbag#isUndefined(a:d) && has_key(a:data, 'complete') | call a:data['complete']() | endif
    if a:t == 2 && !lsp#callbag#isUndefined(a:d) && has_key(a:data, 'error') | call a:data['error'](a:d) | endif
    call a:data['sink'](a:t, a:d)
endfunction
" }}}

" interval() {{{
function! lsp#callbag#interval(period) abort
    let l:data = { 'period': a:period }
    return function('s:intervalPeriod', [l:data])
endfunction

function! s:intervalPeriod(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['i'] = 0
    let a:data['sink'] = a:sink
    let a:data['timer'] = timer_start(a:data['period'], function('s:interval_callback', [a:data]), { 'repeat': -1 })
    call a:sink(0, function('s:interval_sink_callback', [a:data]))
endfunction

function! s:interval_callback(data, ...) abort
    let l:i = a:data['i']
    let a:data['i'] = a:data['i'] + 1
    call a:data['sink'](1, l:i)
endfunction

function! s:interval_sink_callback(data, t, ...) abort
    if a:t == 2 | call timer_stop(a:data['timer']) | endif
endfunction
" }}}

" delay() {{{
function! lsp#callbag#delay(period) abort
    let l:data = { 'period': a:period }
    return function('s:delayPeriod', [l:data])
endfunction

function! s:delayPeriod(data, source) abort
    let a:data['source'] = a:source
    return function('s:delayFactory', [a:data])
endfunction

function! s:delayFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:delaySourceCallback', [a:data]))
endfunction

function! s:delaySourceCallback(data, t, d) abort
    if a:t != 1
        call a:data['sink'](a:t, a:d)
        return
    endif
    let a:data['d'] = a:d
    call timer_start(a:data['period'], function('s:delayTimerCallback', [a:data]))
endfunction

function! s:delayTimerCallback(data, ...) abort
    call a:data['sink'](1, a:data['d'])
endfunction
" }}}

" take() {{{
function! lsp#callbag#take(max) abort
    let l:data = { 'max': a:max }
    return function('s:takeMax', [l:data])
endfunction

function! s:takeMax(data, source) abort
    let a:data['source'] = a:source
    return function('s:takeMaxSource', [a:data])
endfunction

function! s:takeMaxSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['taken'] = 0
    let a:data['end'] = 0
    let a:data['sink'] = a:sink
    let a:data['talkback'] = function('s:takeTalkback', [a:data])
    call a:data['source'](0, function('s:takeSourceCallback', [a:data]))
endfunction

function! s:takeTalkback(data, t, d) abort
    if a:t == 2
        let a:data['end'] = 1
        call a:data['sourceTalkback'](a:t, a:d)
    elseif a:data['taken'] < a:data['max']
        call a:data['sourceTalkback'](a:t, a:d)
    endif
endfunction

function! s:takeSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['sourceTalkback'] = a:d
        call a:data['sink'](0, a:data['talkback'])
    elseif a:t == 1
        if a:data['taken'] < a:data['max']
            let a:data['taken'] = a:data['taken'] + 1
            call a:data['sink'](a:t, a:d)
            if a:data['taken'] == a:data['max'] && !a:data['end']
                let a:data['end'] = 1
                call a:data['sink'](2, lsp#callbag#undefined())
                call a:data['sourceTalkback'](2, lsp#callbag#undefined())
            endif
        endif
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" skip() {{{
function! lsp#callbag#skip(max) abort
    let l:data = { 'max': a:max }
    return function('s:skipMax', [l:data])
endfunction

function! s:skipMax(data, source) abort
    let a:data['source'] = a:source
    return function('s:skipMaxSource', [a:data])
endfunction

function! s:skipMaxSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['skipped'] = 0
    call a:data['source'](0, function('s:skipSouceCallback', [a:data]))
endfunction

function! s:skipSouceCallback(data, t, d) abort
    if a:t == 0
        let a:data['talkback'] = a:d
        call a:data['sink'](a:t, a:d)
    elseif a:t == 1
        if a:data['skipped'] < a:data['max']
            let a:data['skipped'] = a:data['skipped'] + 1
            call a:data['talkback'](1, lsp#callbag#undefined())
        else
            call a:data['sink'](a:t, a:d)
        endif
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" map() {{{
function! lsp#callbag#map(F) abort
    let l:data = { 'f': a:F }
    return function('s:mapF', [l:data])
endfunction

function! s:mapF(data, source) abort
    let a:data['source'] = a:source
    return function('s:mapFSource', [a:data])
endfunction

function! s:mapFSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:mapFSourceCallback', [a:data]))
endfunction

function! s:mapFSourceCallback(data, t, d) abort
    call a:data['sink'](a:t, a:t == 1 ? a:data['f'](a:d) : a:d)
endfunction
" }}}

" filter() {{{
function! lsp#callbag#filter(condition) abort
    let l:data = { 'condition': a:condition }
    return function('s:filterCondition', [l:data])
endfunction

function! s:filterCondition(data, source) abort
    let a:data['source'] = a:source
    return function('s:filterConditionSource', [a:data])
endfunction

function! s:filterConditionSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:filterSourceCallback', [a:data]))
endfunction

function! s:filterSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['talkback'] = a:d
        call a:data['sink'](a:t, a:d)
    elseif a:t == 1
        if a:data['condition'](a:d)
            call a:data['sink'](a:t, a:d)
        else
            call a:data['talkback'](1, lsp#callbag#undefined())
        endif
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" fromEvent() {{{
let s:event_prefix_index = 0
function! lsp#callbag#fromEvent(events, ...) abort
    let l:data = { 'events': a:events }
    if a:0 > 0
        let l:data['augroup'] = a:1
    else
        let l:data['augroup'] = '__callbag_fromEvent_prefix_' . s:event_prefix_index . '__'
        let s:event_prefix_index = s:event_prefix_index + 1
    endif
    return function('s:fromEventFactory', [l:data])
endfunction

let s:event_handler_index = 0
let s:event_handlers_data = {}
function! s:fromEventFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink']  = a:sink
    let a:data['disposed'] = 0
    let a:data['handler'] = function('s:fromEventHandlerCallback', [a:data])
    let a:data['handler_index'] = s:event_handler_index
    let s:event_handler_index = s:event_handler_index + 1
    call a:sink(0, function('s:fromEventSinkHandler', [a:data]))

    if a:data['disposed'] | return | endif
    let s:event_handlers_data[a:data['handler_index']] = a:data

    execute 'augroup ' . a:data['augroup']
    execute 'autocmd!'
    let l:events = type(a:data['events']) == type('') ? [a:data['events']] : a:data['events']
    for l:event in l:events
        let l:exec =  'call s:notify_event_handler(' . a:data['handler_index'] . ')'
        if type(l:event) == type('')
            execute 'au ' . l:event . ' * ' . l:exec
        else
            execute 'au ' . join(l:event, ' ') .' ' .  l:exec
        endif
    endfor
    execute 'augroup end'
endfunction

function! s:fromEventHandlerCallback(data) abort
    " send v:event if it exists
    call a:data['sink'](1, lsp#callbag#undefined())
endfunction

function! s:fromEventSinkHandler(data, t, ...) abort
    if a:t != 2 | return | endif
    let a:data['disposed'] = 1
    execute 'augroup ' a:data['augroup']
    autocmd!
    execute 'augroup end'
    if has_key(s:event_handlers_data, a:data['handler_index'])
        call remove(s:event_handlers_data, a:data['handler_index'])
    endif
endfunction

function! s:notify_event_handler(index) abort
    let l:data = s:event_handlers_data[a:index]
    call l:data['handler']()
endfunction
" }}}

" fromPromise() {{{
function! lsp#callbag#fromPromise(promise) abort
    let l:data = { 'promise': a:promise }
    return function('s:fromPromiseFactory', [l:data])
endfunction

function! s:fromPromiseFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['ended'] = 0
    call a:data['promise'].then(
        \ function('s:fromPromiseOnFulfilledCallback', [a:data]),
        \ function('s:fromPromiseOnRejectedCallback', [a:data]),
        \ )
    call a:sink(0, function('s:fromPromiseSinkCallback', [a:data]))
endfunction

function! s:fromPromiseOnFulfilledCallback(data, ...) abort
    if a:data['ended'] | return | endif
    call a:data['sink'](1, a:0 > 0 ? a:1 : lsp#callbag#undefined())
    if a:data['ended'] | return | endif
    call a:data['sink'](2, lsp#callbag#undefined())
endfunction

function! s:fromPromiseOnRejectedCallback(data, err) abort
    if a:data['ended'] | return | endif
    call a:data['sink'](2, a:err)
endfunction

function! s:fromPromiseSinkCallback(data, t, ...) abort
    if a:t == 2 | let a:data['ended'] = 1 | endif
endfunction
" }}}

" debounceTime() {{{
function! lsp#callbag#debounceTime(duration) abort
    let l:data = { 'duration': a:duration }
    return function('s:debounceTimeDuration', [l:data])
endfunction

function! s:debounceTimeDuration(data, source) abort
    let a:data['source'] = a:source
    return function('s:debounceTimeDurationSource', [a:data])
endfunction

function! s:debounceTimeDurationSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:debounceTimeSourceCallback', [a:data]))
endfunction

function! s:debounceTimeSourceCallback(data, t, d) abort
    if has_key(a:data, 'timer') | call timer_stop(a:data['timer']) | endif
    if a:t == 1
        let a:data['timer'] = timer_start(a:data['duration'], function('s:debounceTimeTimerCallback', [a:data, a:d]))
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction

function! s:debounceTimeTimerCallback(data, d, ...) abort
    call a:data['sink'](1, a:d)
endfunction
" }}}

" subscribe() {{{
function! lsp#callbag#subscribe(...) abort
    let l:data = {}
    if a:0 > 0 && type(a:1) == type({}) " a:1 { next, error, complete }
        if has_key(a:1, 'next') | let l:data['next'] = a:1['next'] | endif
        if has_key(a:1, 'error') | let l:data['error'] = a:1['error'] | endif
        if has_key(a:1, 'complete') | let l:data['complete'] = a:1['complete'] | endif
    else " a:1 = next, a:2 = error, a:3 = complete
        if a:0 >= 1 | let l:data['next'] = a:1 | endif
        if a:0 >= 2 | let l:data['error'] = a:2 | endif
        if a:0 >= 3 | let l:data['complete'] = a:3 | endif
    endif
    return function('s:subscribeListener', [l:data])
endfunction

function! s:subscribeListener(data, source) abort
    call a:source(0, function('s:subscribeSourceCallback', [a:data]))
    return function('s:subscribeDispose', [a:data])
endfunction

function! s:subscribeSourceCallback(data, t, d) abort
    if a:t == 0 | let a:data['talkback'] = a:d | endif
    if a:t == 1 && has_key(a:data, 'next') | call a:data['next'](a:d) | endif
    if a:t == 1 || a:t == 0 | call a:data['talkback'](1, lsp#callbag#undefined()) | endif
    if a:t == 2 && lsp#callbag#isUndefined(a:d) && has_key(a:data, 'complete') | call a:data['complete']() | endif
    if a:t == 2 && !lsp#callbag#isUndefined(a:d) && has_key(a:data, 'error') | call a:data['error'](a:d) | endif
endfunction

function! s:subscribeDispose(data, ...) abort
    if has_key(a:data, 'talkback') | call a:data['talkback'](2, lsp#callbag#undefined()) | endif
endfunction
" }}}

" toList() {{{
function! lsp#callbag#toList() abort
    let l:data = { 'done': 0, 'items': [], 'unsubscribed': 0 }
    return function('s:toListFactory', [l:data])
endfunction

function! s:toListFactory(data, source) abort
    let a:data['unsubscribe'] = lsp#callbag#subscribe(
        \ function('s:toListOnNext', [a:data]),
        \ function('s:toListOnError', [a:data]),
        \ function('s:toListOnComplete', [a:data])
        \ )(a:source)
    if a:data['done'] | call s:toListUnsubscribe(a:data) | endif
    return {
        \ 'unsubscribe': function('s:toListUnsubscribe', [a:data]),
        \ 'wait': function('s:toListWait', [a:data])
        \ }
endfunction

function! s:toListUnsubscribe(data) abort
    if !has_key(a:data, 'unsubscribe') | return | endif
    if !a:data['unsubscribed']
        call a:data['unsubscribe']()
        let a:data['unsubscribed'] = 1
        if !a:data['done']
            let a:data['done'] = 1
            try
                throw 'lsp#callbag toList() is already unsubscribed.'
            catch
                let a:data['error'] = v:exception . ' ' . v:throwpoint
            endtry
        endif
    endif
endfunction

function! s:toListOnNext(data, item) abort
    call add(a:data['items'], a:item)
endfunction

function! s:toListOnError(data, error) abort
    let a:data['done'] = 1
    let a:data['error'] = a:error
    call s:toListUnsubscribe(a:data)
endfunction

function! s:toListOnComplete(data) abort
    let a:data['done'] = 1
    call s:toListUnsubscribe(a:data)
endfunction

function! s:toListWait(data, ...) abort
    if a:data['done']
        if has_key(a:data, 'error')
            throw a:data['error']
        else
            return a:data['items']
        endif
    else
        let l:opt = a:0 > 0 ? copy(a:1) : {}
        let l:opt['timedout'] = 0
        let l:opt['sleep'] = get(l:opt, 'sleep', 1)
        let l:opt['timeout'] = get(l:opt, 'timeout', -1)

        if l:opt['timeout'] > -1
            let l:opt['timer'] = timer_start(l:opt['timeout'], function('s:toListTimeoutCallback', [l:opt]))
        endif

        while !a:data['done'] && !l:opt['timedout']
            exec 'sleep ' . l:opt['sleep'] . 'm'
        endwhile

        if has_key(l:opt, 'timer')
            silent! call timer_stop(l:opt['timer'])
        endif

        if l:opt['timedout']
            throw 'lsp#callbag toList().wait() timedout.'
        endif

        if has_key(a:data, 'error')
            throw a:data['error']
        else
            return a:data['items']
        endif
    endif
endfunction

function! s:toListTimeoutCallback(opt, ...) abort
    let a:opt['timedout'] = 1
endfunction
" }}}

" throwError() {{{
function! lsp#callbag#throwError(error) abort
    let l:data = { 'error': a:error }
    return function('s:throwErrorFactory', [l:data])
endfunction

function! s:throwErrorFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['disposed'] = 0
    call a:sink(0, function('s:throwErrorSinkCallback', [a:data]))
    if a:data['disposed'] | return | endif
    call a:sink(2, a:data['error'])
endfunction

function! s:throwErrorSinkCallback(data, t, ...) abort
    if a:t != 2 | return | endif
    let a:data['disposed'] = 1
endfunction
" }}}

" of() {{{
function! lsp#callbag#of(...) abort
    let l:data = { 'values': a:000 }
    return function('s:listFactory', [l:data])
endfunction
" }}}

" fromList() {{{
function! lsp#callbag#fromList(list) abort
    let l:data = { 'values': a:list }
    return function('s:listFactory', [l:data])
endfunction

function! s:listFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['disposed'] = 0
    call a:sink(0, function('s:listSinkCallback', [a:data]))
    let l:i = 0
    let l:n = len(a:data['values'])
    while l:i < l:n
        if a:data['disposed'] | break | endif
        call a:sink(1, a:data['values'][l:i])
        let l:i += 1
    endwhile
    if a:data['disposed'] | return | endif
    call a:sink(2, lsp#callbag#undefined())
endfunction


function! s:listSinkCallback(data, t, ...) abort
    if a:t != 2 | return | endif
    let a:data['disposed'] = 1
endfunction
" }}}

" merge() {{{
function! lsp#callbag#merge(...) abort
    let l:data = { 'sources': a:000 }
    return function('s:mergeFactory', [l:data])
endfunction

function! s:mergeFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['n'] = len(a:data['sources'])
    let a:data['sourceTalkbacks'] = []
    let a:data['startCount'] = 0
    let a:data['endCount'] = 0
    let a:data['ended'] = 0
    let a:data['talkback'] = function('s:mergeTalkbackCallback', [a:data])
    let l:i = 0
    while l:i < a:data['n']
        if a:data['ended'] | return | endif
        call a:data['sources'][l:i](0, function('s:mergeSourceCallback', [a:data, l:i]))
        let l:i += 1
    endwhile
endfunction

function! s:mergeTalkbackCallback(data, t, d) abort
    if a:t == 2 | let a:data['ended'] = 1 | endif
    let l:i = 0
    while l:i < a:data['n']
        if l:i < len(a:data['sourceTalkbacks']) && a:data['sourceTalkbacks'][l:i] != 0
            call a:data['sourceTalkbacks'][l:i](a:t, a:d)
        endif
        let l:i += 1
    endwhile
endfunction

function! s:mergeSourceCallback(data, i, t, d) abort
    if a:t == 0
        call insert(a:data['sourceTalkbacks'], a:d, a:i)
        let a:data['startCount'] += 1
        if a:data['startCount'] == 1 | call a:data['sink'](0, a:data['talkback']) | endif
    elseif a:t == 2 && !lsp#callbag#isUndefined(a:d)
        let a:data['ended'] = 1
        let l:j = 0
        while l:j < a:data['n']
            if l:j != a:i && l:j < len(a:data['sourceTalkbacks']) && a:data['sourceTalkbacks'][l:j] != 0
                call a:data['sourceTalkbacks'][l:j](2, lsp#callbag#undefined())
            endif
            let l:j += 1
        endwhile
        call a:data['sink'](2, a:d)
    elseif a:t == 2
        let a:data['sourceTalkbacks'][a:i] = 0
        let a:data['endCount'] += 1
        if a:data['endCount'] == a:data['n'] | call a:data['sink'](2, lsp#callbag#undefined()) | endif
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" concat() {{{
function! lsp#callbag#concat(...) abort
    let l:data = { 'sources': a:000 }
    return function('s:concatFactory', [l:data])
endfunction

let s:concatUniqueToken = '__callback__concat_unique_token__'
function! s:concatFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['n'] = len(a:data['sources'])
    if a:data['n'] == 0
        call a:data['sink'](0, function('s:noop'))
        call a:data['sink'](2, lsp#callbag#undefined())
        return
    endif
    let a:data['i'] = 0
    let a:data['lastPull'] = s:concatUniqueToken
    let a:data['talkback'] = function('s:concatTalkbackCallback', [a:data])
    let a:data['next'] = function('s:concatNext', [a:data])
    call a:data['next']()
endfunction

function! s:concatTalkbackCallback(data, t, d) abort
    if a:t == 1 | let a:data['lastPull'] = a:d | endif
    call a:data['sourceTalkback'](a:t, a:d)
endfunction

function! s:concatNext(data) abort
    if a:data['i'] == a:data['n']
        call a:data['sink'](2, lsp#callbag#undefined())
        return
    endif
    call a:data['sources'][a:data['i']](0, function('s:concatSourceCallback', [a:data]))
endfunction

function! s:concatSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['sourceTalkback'] = a:d
        if a:data['i'] == 0
            call a:data['sink'](0, a:data['talkback'])
        elseif (a:data['lastPull']) != s:concatUniqueToken
            call a:data['sourceTalkback'](1, a:data['lastPull'])
        endif
    elseif a:t == 2 && a:d != lsp#callbag#undefined()
        call a:data['sink'](2, a:d)
    elseif a:t == 2 
        let a:data['i'] = a:data['i'] + 1
        call a:data['next']()
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" combine() {{{
function! lsp#callbag#combine(...) abort
    let l:data = { 'sources': a:000 }
    return function('s:combineFactory', [l:data])
endfunction

let s:combineEmptyToken = '__callback__combine_empty_token__'
function! s:combineFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['n'] = len(a:data['sources'])
    if a:data['n'] == 0
        call a:data['sink'](0, function('s:noop'))
        call a:data['sink'](1, [])
        call a:data['sink'](2, lsp#callbag#undefined())
        return
    endif
    let a:data['Ns'] = a:data['n'] " start counter
    let a:data['Nd'] = a:data['n'] " data counter
    let a:data['Ne'] = a:data['n'] " end counter
    let a:data['vals'] = s:createArrayWithSize(a:data['n'], lsp#callbag#undefined())
    let a:data['sourceTalkbacks'] = s:createArrayWithSize(a:data['n'], lsp#callbag#undefined())
    let a:data['talkback'] = function('s:combineTalkbackCallback', [a:data])
    let l:i = 0
    for l:Source in a:data['sources']
        let a:data['vals'][l:i] = s:combineEmptyToken
        call l:Source(0, function('s:combineSourceCallback', [a:data, l:i]))
        let l:i = l:i + 1
    endfor
endfunction

function! s:combineTalkbackCallback(data, t, d) abort
    if a:t == 0 | return | endif
    let l:i = 0
    while l:i < a:data['n']
        call a:data['sourceTalkbacks'][l:i](a:t, a:d)
        let l:i = l:i + 1
    endwhile
endfunction

function! s:combineSourceCallback(data, i, t, d) abort
    if a:t == 0
        let a:data['sourceTalkbacks'][a:i] = a:d
        let a:data['Ns'] = a:data['Ns'] - 1
        if a:data['Ns'] == 0 | call a:data['sink'](0, a:data['talkback']) | endif
    elseif a:t == 1
        if a:data['Nd'] <= 0
            let l:_Nd = 0
        else
            if a:data['vals'][a:i] == s:combineEmptyToken
                let a:data['Nd'] = a:data['Nd'] - 1
            endif
            let l:_Nd = a:data['Nd']
        endif
        let a:data['vals'][a:i] = a:d
        if l:_Nd == 0
            let l:arr = s:createArrayWithSize(a:data['n'], lsp#callbag#undefined())
            let l:j = 0
            while l:j < a:data['n']
                let l:arr[l:j] = a:data['vals'][l:j]
                let l:j = l:j + 1
            endwhile
            call a:data['sink'](1, l:arr)
        endif
    elseif a:t == 2
        let a:data['Ne'] = a:data['Ne'] - 1
        if a:data['Ne'] == 0
            call a:data['sink'](2, lsp#callbag#undefined())
        endif
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" distinctUntilChanged {{{
function! s:distinctUntilChangedDefaultCompare(a, b) abort
    return a:a == a:b
endfunction

function! lsp#callbag#distinctUntilChanged(...) abort
    let l:data = { 'compare': a:0 == 0 ? function('s:distinctUntilChangedDefaultCompare') : a:1 }
    return function('s:distinctUntilChangedSourceFactory', [l:data])
endfunction

function! s:distinctUntilChangedSourceFactory(data, source) abort
    let a:data['source'] = a:source
    return function('s:distinctUntilChangedSinkFactory', [a:data])
endfunction

function! s:distinctUntilChangedSinkFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['inited'] = 0
    call a:data['source'](0, function('s:distinctUntilChangedSourceCallback', [a:data]))
endfunction

function! s:distinctUntilChangedSourceCallback(data, t, d) abort
    if a:t == 0 | let a:data['talkback'] = a:d | endif
    if a:t != 1
        call a:data['sink'](a:t, a:d)
        return
    endif

    if a:data['inited'] && has_key(a:data, 'prev') && a:data['compare'](a:data['prev'], a:d)
        call a:data['talkback'](1, lsp#callbag#undefined())
        return
    endif

    let a:data['inited'] = 1
    let a:data['prev'] = a:d
    call a:data['sink'](1, a:d)
endfunction
" }}}

" takeUntil() {{{
function! lsp#callbag#takeUntil(notfier) abort
    let l:data = { 'notifier': a:notfier }
    return function('s:takeUntilNotifier', [l:data])
endfunction

function! s:takeUntilNotifier(data, source) abort
    let a:data['source'] = a:source
    return function('s:takeUntilFactory', [a:data])
endfunction

let s:takeUntilUniqueToken = '__callback__take_until_unique_token__'

function! s:takeUntilFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['inited'] = 1
    let a:data['sourceTalkback'] = 0
    let a:data['notiferTalkback'] = 0
    let a:data['done'] = s:takeUntilUniqueToken
    call a:data['source'](0, function('s:takeUntilSourceCallback', [a:data]))
endfunction

function! s:takeUntilSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['sourceTalkback'] = a:d
        call a:data['notifier'](0, function('s:takeUntilNotifierCallback', [a:data]))
        let a:data['inited'] = 1
        call a:data['sink'](0, function('s:takeUntilSinkCallback', [a:data]))
        if a:data['done'] != s:takeUntilUniqueToken | call a:data['sink'](2, a:data['done']) | endif
        return
    endif
    if a:t == 2
        call a:data['notifierTalkback'](2, lsp#callbag#undefined())
    endif
    if a:data['done'] == s:takeUntilUniqueToken
        call a:data['sink'](a:t, a:d)
    endif
endfunction

function! s:takeUntilNotifierCallback(data, t, d) abort
    if a:t == 0
        let a:data['notifierTalkback'] = a:d
        call a:data['notifierTalkback'](1, lsp#callbag#undefined())
        return
    endif
    if a:t == 1
        let a:data['done'] = 0
        call a:data['notifierTalkback'](2, lsp#callbag#undefined())
        call a:data['sourceTalkback'](2, lsp#callbag#undefined())
        if a:data['inited'] | call a:data['sink'](2, lsp#callbag#undefined()) | endif
        return
    endif
    if a:t ==2
        let a:data['notifierTalkback'] = 0
        let a:data['done'] = a:d
        if a:d != 0
            call a:data['sourceTalkback'](2, lsp#callbag#undefined())
            if a:data['inited'] | call a:data['sink'](a:t, a:d) | endif
        endif
    endif
endfunction

function! s:takeUntilSinkCallback(data, t, d) abort
    if a:data['done'] != s:takeUntilUniqueToken | return | endif
    if a:t == 2 && has_key(a:data, 'notifierTalkback') && a:data['notifierTalkback'] != 0 | call a:data['notifierTalkback'](2, lsp#callbag#undefined()) | endif
    call a:data['sourceTalkback'](a:t, a:d)
endfunction
" }}}

" takeWhile() {{{
function! lsp#callbag#takeWhile(predicate) abort
    let l:data = { 'predicate': a:predicate }
    return function('s:takeWhileFactory', [l:data])
endfunction

function! s:takeWhileFactory(data, source) abort
    let a:data['source'] = a:source
    return function('s:takeWhileSourceFactory', [a:data])
endfunction

function! s:takeWhileSourceFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:takeWhileSourceCallback', [a:data]))
endfunction

function! s:takeWhileSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['sourceTalkback'] = a:d
    endif

    if a:t == 1 && !a:data['predicate'](a:d)
        call a:data['sourceTalkback'](2, lsp#callbag#undefined())
        call a:data['sink'](2, lsp#callbag#undefined())
        return
    endif

    call a:data['sink'](a:t, a:d)
endfunction
" }}}

" group() {{{
function! lsp#callbag#group(n) abort
    let l:data = { 'n': a:n }
    return function('s:groupN', [l:data])
endfunction

function! s:groupN(data, source) abort
    let a:data['source'] = a:source
    return function('s:groupFactory', [a:data])
endfunction

function! s:groupFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['chunk'] = []
    call a:data['source'](0, function('s:groupSourceCallback', [a:data]))
endfunction

function! s:groupSourceCallback(data, t, d) abort
    if a:t == 0 | let a:data['talkback'] = a:d | endif
    if a:t == 1
        call add(a:data['chunk'], a:d)
        if len(a:data['chunk']) == a:data['n']
            call a:data['sink'](a:t, remove(a:data['chunk'], 0, a:data['n'] - 1))
        endif
        call a:data['talkback'](1, lsp#callbag#undefined())
    else
        if a:t == 2 && len(a:data['chunk']) > 0
            call a:data['sink'](1, remove(a:data['chunk'], 0, len(a:data['chunk']) - 1))
        else
            call a:data['sink'](a:t, a:d)
        endif
    endif
endfunction
" }}}

" flatten() {{{
function! lsp#callbag#flatten() abort
    return function('s:flattenSource')
endfunction

function! s:flattenSource(source) abort
    let l:data = { 'source': a:source }
    return function('s:flattenFactory', [l:data])
endfunction

function! s:flattenFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['outerEnded'] = 0
    let a:data['outerTalkback'] = 0
    let a:data['innerTalkback'] = 0
    let a:data['talkback'] = function('s:flattenTalkbackCallback', [a:data])
    call a:data['source'](0, function('s:flattenSourceCallback', [a:data]))
endfunction

function! s:flattenTalkbackCallback(data, t, d) abort
    if a:t == 1
        if a:data['innerTalkback'] != 0
            call a:data['innerTalkback'](1, a:d)
        else
            call a:data['outerTalkback'](1, a:d)
        endif
    endif
    if a:t == 2
        if a:data['innerTalkback'] != 0 | call a:data['innerTalkback'](2, lsp#callbag#undefined()) | endif
        call a:data['outerTalkback'](2, lsp#callbag#undefined())
    endif
endfunction

function! s:flattenSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['outerTalkback'] = a:d
        call a:data['sink'](0, a:data['talkback'])
    elseif a:t == 1
        let l:InnerSource = a:d
        if a:data['innerTalkback'] != 0 | call a:data['innerTalkback'](2, lsp#callbag#undefined()) | endif
        call l:InnerSource(0, function('s:flattenInnerSourceCallback', [a:data]))
    elseif a:t == 2 && !lsp#callbag#isUndefined(a:d)
        if a:data['innerTalkback'] != 0 | call a:data['innerTalkback'](2, lsp#callbag#undefined()) | endif
        call a:data['outerTalkback'](1, a:d)
    elseif a:t == 2
        if a:data['innerTalkback'] == 0
            call a:data['sink'](2, lsp#callbag#undefined())
        else
            let a:data['outerEnded'] = 1
        endif
    endif
endfunction

function! s:flattenInnerSourceCallback(data, t, d) abort
    if a:t == 0
        let a:data['innerTalkback'] = a:d
        call a:data['innerTalkback'](1, lsp#callbag#undefined())
    elseif a:t == 1
        call a:data['sink'](1, a:d)
    elseif a:t == 2 && !lsp#callbag#isUndefined(a:d)
        call a:data['outerTalkback'](2, lsp#callbag#undefined())
        call a:data['sink'](2, a:d)
    elseif a:t == 2
        if a:data['outerEnded'] != 0
            call a:data['sink'](2, lsp#callbag#undefined())
        else
            let a:data['innerTalkback'] = 0
            call a:data['outerTalkback'](1, lsp#callbag#undefined())
        endif
    endif
endfunction
" }}}

" flatMap() {{{
function! lsp#callbag#flatMap(F) abort
    return lsp#callbag#operate(
        \ lsp#callbag#map(a:F),
        \ lsp#callbag#flatten(),
        \ )
endfunction
" }}}

" scan() {{{
function! lsp#callbag#scan(reducer, seed) abort
    let l:data = { 'reducer': a:reducer, 'seed': a:seed }
    return function('s:scanSource', [l:data])
endfunction

function! s:scanSource(data, source) abort
    let a:data['source'] = a:source
    return function('s:scanFactory', [a:data])
endfunction

function! s:scanFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['acc'] = a:data['seed']
    call a:data['source'](0, function('s:scanSourceCallback', [a:data]))
endfunction

function! s:scanSourceCallback(data, t, d) abort
    if a:t == 1
        let a:data['acc'] = a:data['reducer'](a:data['acc'], a:d)
        call a:data['sink'](1, a:data['acc'])
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" reduce() {{{
function! lsp#callbag#reduce(reducer, seed) abort
    let l:data = { 'reducer': a:reducer, 'seed': a:seed }
    return function('s:reduceSource', [l:data])
endfunction

function! s:reduceSource(data, source) abort
    let a:data['source'] = a:source
    return function('s:reduceFactory', [a:data])
endfunction

function! s:reduceFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    let a:data['acc'] = a:data['seed']
    call a:data['source'](0, function('s:reduceSourceCallback', [a:data]))
endfunction

function! s:reduceSourceCallback(data, t, d) abort
    if a:t == 1
        let a:data['acc'] = a:data['reducer'](a:data['acc'], a:d)
    elseif a:t == 2 && lsp#callbag#isUndefined(a:d)
        call a:data['sink'](1, a:data['acc'])
        call a:data['sink'](2, lsp#callbag#undefined())
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" switchMap() {{{
function! lsp#callbag#switchMap(makeSource, ...) abort
    let l:data = { 'makeSource': a:makeSource }
    if a:0 == 1
        let l:data['combineResults'] = a:1
    else
        let l:data['combineResults'] = function('s:switchMapDefaultCombineResults')
    endif
    return function('s:switchMapSourceCallback', [l:data])
endfunction

function! s:switchMapDefaultCombineResults(a, b) abort
    return a:b
endfunction

function! s:switchMapSourceCallback(data, inputSource) abort
    let a:data['inputSource'] = a:inputSource
    return function('s:switchMapFactory', [a:data])
endfunction

function! s:switchMapFactory(data, start, outputSink) abort
    if a:start != 0 | return | endif
    let a:data['outputSink'] = a:outputSink
    let a:data['sourceEnded'] = 0
    call a:data['inputSource'](0, function('s:switchMapInputSourceCallback', [a:data]))
endfunction

function! s:switchMapInputSourceCallback(data, t, d) abort
    if a:t == 0 | call a:data['outputSink'](a:t, a:d) | endif
    if a:t == 1
        if has_key(a:data, 'currSourceTalkback')
            call a:data['currSourceTalkback'](2, lsp#callbag#undefined())
            call remove(a:data, 'currSourceTalkback')
        endif
        let l:CurrSource = a:data['makeSource'](a:d)
        call l:CurrSource(0, function('s:switchMapCurrSourceCallback', [a:data, a:t, a:d]))
    endif
    if a:t == 2
        let a:data['sourceEnded'] = 1
        if !has_key(a:data, 'currSourceTalkback') | call a:data['outputSink'](a:t, a:d) | endif
    endif
endfunction

function! s:switchMapCurrSourceCallback(data, t, d, currT, currD) abort
    if a:currT == 0 | let a:data['currSourceTalkback'] = a:currD | endif
    if a:currT == 1 | call a:data['outputSink'](a:t, a:data['combineResults'](a:d, a:currD)) | endif
    if (a:currT == 0 || a:currT == 1) && has_key(a:data, 'currSourceTalkback')
        call a:data['currSourceTalkback'](1, lsp#callbag#undefined())
    endif
    if a:currT == 2
        call remove(a:data, 'currSourceTalkback')
        if a:data['sourceEnded'] | call a:data['outputSink'](a:currT, a:currD) | endif
    endif
endfunction
" }}}

" {{{
function! lsp#callbag#share(source) abort
    let l:data = { 'source': a:source, 'sinks': [] }
    return function('s:shareFactory', [l:data])
endfunction

function! s:shareFactory(data, start, sink) abort
    if a:start != 0 | return | endif
    call add(a:data['sinks'], a:sink)

    let a:data['talkback'] = function('s:shareTalkbackCallback', [a:data, a:sink])

    if len(a:data['sinks']) == 1
        call a:data['source'](0, function('s:shareSourceCallback', [a:data, a:sink]))
        return
    endif

    call a:sink(0, a:data['talkback'])
endfunction

function! s:shareTalkbackCallback(data, sink, t, d) abort
    if a:t == 2
        let l:i = 0
        let l:found = 0
        while l:i < len(a:data['sinks'])
            if a:data['sinks'][l:i] == a:sink
                let l:found = 1
                break
            endif
            let l:i += 1
        endwhile

        if l:found
            call remove(a:data['sinks'], l:i)
        endif

        if empty(a:data['sinks'])
            call a:data['sourceTalkback'](2, lsp#callbag#undefined())
        endif
    else
        call a:data['sourceTalkback'](a:t, a:d)
    endif
endfunction

function! s:shareSourceCallback(data, sink, t, d) abort
    if a:t == 0
        let a:data['sourceTalkback'] = a:d
        call a:sink(0, a:data['talkback'])
    else
        for l:S in a:data['sinks']
            call l:S(a:t, a:d)
        endfor
    endif
    if a:t == 2
        let a:data['sinks'] = []
    endif
endfunction
" }}}

" materialize() {{{
function! lsp#callbag#materialize() abort
    let l:data = {}
    return function('s:materializeF', [l:data])
endfunction

function! s:materializeF(data, source) abort
    let a:data['source'] = a:source
    return function('s:materializeFSource', [a:data])
endfunction

function! s:materializeFSource(data, start, sink) abort
    if a:start != 0 | return | endif
    let a:data['sink'] = a:sink
    call a:data['source'](0, function('s:materializeFSourceCallback', [a:data]))
endfunction

function! s:materializeFSourceCallback(data, t, d) abort
    if a:t == 1
        call a:data['sink'](1, lsp#callbag#createNextNotification(a:d))
    elseif a:t == 2
        call a:data['sink'](1, lsp#callbag#isUndefined(a:d)
                    \ ? lsp#callbag#createCompleteNotification()
                    \ : lsp#callbag#createErrorNotification(a:d))
        call a:data['sink'](2, lsp#callbag#undefined())
    else
        call a:data['sink'](a:t, a:d)
    endif
endfunction
" }}}

" Notifications {{{
function! lsp#callbag#createNextNotification(d) abort
    return { 'kind': 'N', 'value': a:d }
endfunction

function! lsp#callbag#createCompleteNotification() abort
    return { 'kind': 'C' }
endfunction

function! lsp#callbag#createErrorNotification(d) abort
    return { 'kind': 'E', 'error': a:d }
endfunction

function! lsp#callbag#isNextNotification(d) abort
    return a:d['kind'] ==# 'N'
endfunction

function! lsp#callbag#isCompleteNotification(d) abort
    return a:d['kind'] ==# 'C'
endfunction

function! lsp#callbag#isErrorNotification(d) abort
    return a:d['kind'] ==# 'E'
endfunction
" }}}

" spawn {{{
" let s:Stdin = lsp#callbag#makeSubject()
" call lsp#callbag#spawn(['bash', '-c', 'read i; echo $i'], {
"   \ 'stdin': s:Stdin,
"   \ 'stdout': 0,
"   \ 'stderr': 0,
"   \ 'exit': 0,
"   \ 'start': 0, " when job starts before subscribing to stdin
"   \ 'ready': 0, " when job starts and after subscribing to stdin
"   \ 'pid': 0,
"   \ 'failOnNonZeroExitCode': 1,
"   \ 'failOnStdinError': 1,
"   \ 'normalize': 'raw' | 'string' | 'array', (defaults to raw),
"   \ 'env': {},
"   \ })
"   call s:Stdin(1, 'hi')
"   call s:Stdin(2, lsp#callbag#undefined()) " requried to close stdin
function! lsp#callbag#spawn(cmd, ...) abort
    let l:data = { 'cmd': a:cmd, 'opt': a:0 > 0 ? copy(a:000[0]) : {} }
    return lsp#callbag#create(function('s:spawnCreate', [l:data]))
endfunction

function! s:spawnCreate(data, next, error, complete) abort
    let a:data['next'] = a:next
    let a:data['error'] = a:error
    let a:data['complete'] = a:complete
    let a:data['state'] = {}
    let a:data['dispose'] = 0
    let a:data['exit'] = 0
    let a:data['close'] = 0

    let l:normalize = get(a:data['opt'], 'normalize', 'raw')

    if has('nvim')
        let a:data['jobopt'] = {
            \ 'on_exit': function('s:spawnNeovimOnExit', [a:data]),
            \ }
        if l:normalize ==# 'string'
            let a:data['normalize'] = function('s:spawnNormalizeNeovimString')
        else
            let a:data['normalize'] = function('s:spawnNormalizeRaw')
        endif
        if get(a:data['opt'], 'stdout', 0) | let a:data['jobopt']['on_stdout'] = function('s:spawnNeovimOnStdout', [a:data]) | endif
        if get(a:data['opt'], 'stderr', 0) | let a:data['jobopt']['on_stderr'] = function('s:spawnNeovimOnStderr', [a:data]) | endif
        if has_key(a:data['opt'], 'env') | let a:data['jobopt']['env'] = a:data['opt']['env'] | endif
        let a:data['jobid'] = jobstart(a:data['cmd'], a:data['jobopt'])
    else
        let a:data['jobopt'] = {
            \ 'exit_cb': function('s:spawnVimExitCb', [a:data]),
            \ 'close_cb': function('s:spawnVimCloseCb', [a:data]),
            \ }
        if get(a:data['opt'], 'stdout', 0) | let a:data['jobopt']['out_cb'] = function('s:spawnVimOutCb', [a:data]) | endif
        if get(a:data['opt'], 'stderr', 0) | let a:data['jobopt']['err_cb'] = function('s:spawnVimErrCb', [a:data]) | endif
        if has_key(a:data['opt'], 'env') | let a:data['jobopt']['env'] = a:data['opt']['env'] | endif
        if l:normalize ==# 'array'
            let a:data['normalize'] = function('s:spawnNormalizeVimArray')
        else
            let a:data['normalize'] = function('s:spawnNormalizeRaw')
        endif
        if has('patch-8.1.350') | let a:data['jobopt']['noblock'] = 1 | endif
        let a:data['stdinBuffer'] = ''
        let a:data['job'] = job_start(a:data['cmd'], a:data['jobopt'])
        let a:data['jobchannel'] = job_getchannel(a:data['job'])
        let a:data['jobid'] = ch_info(a:data['jobchannel'])['id']
    endif

    if a:data['jobid'] < 0 | return | endif " jobstart failed. on_exit will notify with error

    if get(a:data['opt'], 'pid', 0)
        if has('nvim')
            let a:data['pid'] = jobpid(a:data['jobid'])
            let l:startdata['pid'] = a:data['pid']
        else
            let l:jobinfo = job_info(a:data['job'])
            if type(l:jobinfo) == type({}) && has_key(l:jobinfo, 'process')
                let a:data['pid'] = l:jobinfo['process']
                let l:startdata['pid'] = a:data['pid']
            endif
        endif
    endif

    if get(a:data['opt'], 'start', 0)
        let l:startdata = { 'id': a:data['jobid'], 'state': a:data['state'] }
        call a:data['next']({ 'event': 'start', 'data': l:startdata })
    endif

    if has_key(a:data['opt'], 'stdin')
        let a:data['stdinDispose'] = lsp#callbag#pipe(
            \ a:data['opt']['stdin'],
            \ lsp#callbag#subscribe({
            \   'next': (has('nvim') ? function('s:spawnNeovimStdinNext', [a:data]) : function('s:spawnVimStdinNext', [a:data])),
            \   'error': (has('nvim') ? function('s:spawnNeovimStdinError', [a:data]) : function('s:spawnVimStdinError', [a:data])),
            \   'complete': (has('nvim') ? function('s:spawnNeovimStdinComplete', [a:data]) : function('s:spawnVimStdinComplete', [a:data])),
            \ }),
            \ )
    endif

    if get(a:data['opt'], 'ready', 0)
        let l:readydata = { 'id': a:data['jobid'], 'state': a:data['state'] }
        if has_key(a:data, 'pid') | let l:readydata['pid'] = a:data['pid'] | endif
        call a:data['next']({ 'event': 'ready', 'data': l:readydata })
    endif

    return function('s:spawnDispose', [a:data])
endfunction

function! s:spawnJobStop(data) abort
    if has('nvim')
        try
            call jobstop(a:data['jobid'])
        catch /^Vim\%((\a\+)\)\=:E900/
            " NOTE:
            " Vim does not raise exception even the job has already closed so fail
            " silently for 'E900: Invalid job id' exception
        endtry
    else
        call job_stop(a:data['job'])
    endif
endfunction

function! s:spawnDispose(data) abort
    let a:data['dispose'] = 1
    call s:spawnJobStop(a:data)
endfunction

function! s:spawnNeovimStdinNext(data, x) abort
    call jobsend(a:data['jobid'], a:x)
endfunction

function! s:spawnVimStdinNext(data, x) abort
    " Ref: https://groups.google.com/d/topic/vim_dev/UNNulkqb60k/discussion
    let a:data['stdinBuffer'] .= a:x
    call s:spawnVimStdinNextFlushBuffer(a:data)
endfunction

function! s:spawnVimStdinNextFlushBuffer(data) abort
    " https://github.com/vim/vim/issues/2548
    " https://github.com/natebosch/vim-lsc/issues/67#issuecomment-357469091
    sleep 1m
    if len(a:data['stdinBuffer']) <= 4096
        call ch_sendraw(a:data['jobchannel'], a:data['stdinBuffer'])
        let a:data['stdinBuffer'] = ''
    else
        let l:to_send = a:data['stdinBuffer'][:4095]
        let a:data['stdinBuffer'] = a:data['stdinBuffer'][4096:]
        call ch_sendraw(a:data['jobchannel'], l:to_send)
        call timer_start(1, function('s:spawnVimStdinNextFlushBuffer', [a:data]))
    endif
endfunction

function! s:spawnNeovimStdinError(data, x) abort
    let a:data['stdinError'] = a:x
    if get(a:data['opt'], 'failOnStdinError', 1) | call s:spawnJobStop(a:data) | endif
endfunction

function! s:spawnVimStdinError(data, x) abort
    let a:data['stdinError'] = a:x
    if get(a:data['opt'], 'failOnStdinError', 1) | call s:spawnJobStop(a:data) | endif
endfunction

function! s:spawnNeovimStdinComplete(data) abort
    call chanclose(a:data['jobid'], 'stdin')
endfunction

function! s:spawnVimStdinComplete(data) abort
   " There is no easy way to know when ch_sendraw() finishes writing data
   " on a non-blocking channels -- has('patch-8.1.889') -- and because of
   " this, we cannot safely call ch_close_in().
    while len(a:data['stdinBuffer']) != 0
        sleep 1m
    endwhile
    call ch_close_in(a:data['jobchannel'])
endfunction

function! s:spawnNormalizeRaw(data) abort
    return a:data
endfunction

function! s:spawnNormalizeNeovimString(data) abort
    " convert array to string since neovim uses array split by \n by default
    return join(a:data, "\n")
endfunction

function! s:spawnNormalizeVimArray(data) abort
    " convert string to array since vim uses string by default.
    return split(a:data, "\n", 1)
endfunction

function! s:spawnNeovimOnStdout(data, id, d, event) abort
    call a:data['next']({ 'event': 'stdout', 'data': a:data['normalize'](a:d), 'state': a:data['state'] })
endfunction

function! s:spawnNeovimOnStderr(data, id, d, event) abort
    call a:data['next']({ 'event': 'stderr', 'data': a:data['normalize'](a:d), 'state': a:data['state'] })
endfunction

function! s:spawnNeovimOnExit(data, id, d, event) abort
    let a:data['exit'] = 1
    let a:data['close'] = 1
    let a:data['exitcode'] = a:d
    call s:spawnNotifyExit(a:data)
endfunction

function! s:spawnVimOutCb(data, id, d, ...) abort
    call a:data['next']({ 'event': 'stdout', 'data': a:data['normalize'](a:d), 'state': a:data['state'] })
endfunction

function! s:spawnVimErrCb(data, id, d, ...) abort
    call a:data['next']({ 'event': 'stderr', 'data': a:data['normalize'](a:d), 'state': a:data['state'] })
endfunction

function! s:spawnVimExitCb(data, id, d) abort
    let a:data['exit'] = 1
    let a:data['exitcode'] = a:d
    " for more info refer to :h job-start
    " job may exit before we read the output and output may be lost.
    " in unix this happens because closing the write end of a pipe
    " causes the read end to get EOF.
    " close and exit has race condition, so wait for both to complete
    if a:data['close'] && a:data['exit']
        call s:spawnNotifyExit(a:data)
    endif
endfunction

function! s:spawnVimCloseCb(data, id) abort
    let a:data['close'] = 1
    if a:data['close'] && a:data['exit']
        call s:spawnNotifyExit(a:data)
    endif
endfunction

function! s:spawnNotifyExit(data) abort
    if a:data['dispose'] | return | end
    if has_key(a:data, 'stdinDispose') | call a:data['stdinDispose']() | endif
    if get(a:data['opt'], 'failOnStdinError', 1) && has_key(a:data, 'stdinError')
        call a:data['error'](a:data['stdinError'])
        return
    endif
    if get(a:data['opt'], 'exit', 0)
        call a:data['next']({ 'event': 'exit', 'data': a:data['exitcode'], 'state': a:data['state'] })
    endif
    if get(a:data['opt'], 'failOnNonZeroExitCode', 1) && a:data['exitcode'] != 0
        call a:data['error']('Spawn for job ' . a:data['jobid'] .' failed with exit code ' . a:data['exitcode'] . '. ')
    else
        call a:data['complete']()
    endif
endfunction
" }}}

" vim:ts=4:sw=4:ai:foldmethod=marker:foldlevel=0:
