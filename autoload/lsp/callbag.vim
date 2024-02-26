" https://github.com/prabirshrestha/callbag.vim#6951996ea16ab096b35630f9ae744793be896b9a
"    :CallbagEmbed path=autoload/lsp/callbag.vim namespace=lsp#callbag

function! s:noop(...) abort
endfunction

let s:undefined_token = '__lsp__callbag_undefined__'
let s:str_type = type('')
let s:func_type = type(function('s:noop'))

" ***** UTILS ***** {{{

" undefined() {{{
function! lsp#callbag#undefined() abort
    return s:undefined_token
endfunction
" }}}

" isUndefined() {{{
function! lsp#callbag#isUndefined(d) abort
    return type(a:d) == s:str_type && a:d ==# s:undefined_token
endfunction
" }}}

" pipe() {{{
function! lsp#callbag#pipe(...) abort
    if a:0 == 0
        return function('s:pipeIdentity')
    elseif a:0 == 1
        return a:1
    else
        let l:Res = a:1
        let l:i = 1
        while l:i < a:0
            let l:Res = a:000[l:i](l:Res)
            let l:i = l:i + 1
        endwhile
        return l:Res
    endif
endfunction

function! s:pipeIdentity(x) abort
    return a:x
endfunction
" }}}

" subscribe() {{{
function! lsp#callbag#subscribe(...) abort
    " listener
    let l:ctxListener = {}
    let l:observer = {}
    if a:0 > 0 && type(a:1) == type({}) " a:1 { next, error, complete }
        if has_key(a:1, 'next') | let l:observer['next'] = a:1['next'] | endif
        if has_key(a:1, 'error') | let l:observer['error'] = a:1['error'] | endif
        if has_key(a:1, 'complete') | let l:observer['complete'] = a:1['complete'] | endif
    else " a:1 = next, a:2 = error, a:3 = complete
        if a:0 >= 1 | let l:observer['next'] = a:1 | endif
        if a:0 >= 2 | let l:observer['error'] = a:2 | endif
        if a:0 >= 3 | let l:observer['complete'] = a:3 | endif
    endif
    let l:ctxListener['o'] = l:observer
    return function('s:subscribeSourceFn', [l:ctxListener])
endfunction

function! s:subscribeSourceFn(ctxListener, source) abort
    let l:ctxSource = { 'source': a:source, 'ctxListener': a:ctxListener }
    call a:source(0, function('s:subscribeSinkFn', [l:ctxSource]))
    return function('s:subscribeDispose', [l:ctxSource])
endfunction

function! s:subscribeSinkFn(ctxSource, t, d) abort
    if a:t == 0
        let a:ctxSource['sourceTalkback'] = a:d
    elseif a:t == 1
        if has_key(a:ctxSource['ctxListener']['o'], 'next') | call a:ctxSource['ctxListener']['o']['next'](a:d) | endif
    elseif a:t == 2
        if lsp#callbag#isUndefined(a:d)
            if has_key(a:ctxSource['ctxListener']['o'], 'complete') | call a:ctxSource['ctxListener']['o']['complete']() | endif
        else
            if has_key(a:ctxSource['ctxListener']['o'], 'error') | call a:ctxSource['ctxListener']['o']['error'](a:d) | endif
        endif
    endif
endfunction

function! s:subscribeDispose(ctxSource) abort
    if has_key(a:ctxSource, 'sourceTalkback') | call a:ctxSource['sourceTalkback'](2, lsp#callbag#undefined()) | endif
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

" }}}

" ***** SUBJECT ***** {{{

" asObservable() {{{
function! s:asObservable(o) abort
    return lsp#callbag#create(function('s:asObservableCreate', [a:o]))
endfunction

function! s:asObservableCreate(o, next, error, complete) abort
    return a:o['subscribe']({
        \ 'next': function('s:asObservableNext', [a:next]),
        \ 'error': function('s:asObservableError', [a:error]),
        \ 'complete': function('s:asObservableComplete', [a:complete]),
        \ })
endfunction

function! s:asObservableNext(next, value) abort
    call a:next(a:value)
endfunction

function! s:asObservableError(error, err) abort
    call a:error(a:err)
endfunction

function! s:asObservableComplete(complete) abort
    call a:complete()
endfunction
" }}}

" createSubject() {{{
function! lsp#callbag#createSubject() abort
    let l:ctx = { 'observers': [] }
    let l:ctx['next'] = function('s:createSubjectNextFn', [l:ctx])
    let l:ctx['error'] = function('s:createSubjectErrorFn', [l:ctx])
    let l:ctx['complete'] = function('s:createSubjectCompleteFn', [l:ctx])
    let l:ctx['unsubscribe'] = function('s:createSubjectUnsubscribeSubjectFn', [l:ctx])
    let l:ctx['subscribe'] = function('s:createSubjectSubscribeSubjectFn', [l:ctx])
    let l:ctx['asObservable'] = function('s:asObservable', [l:ctx])
    return {
        \ 'next': l:ctx['next'],
        \ 'error': l:ctx['error'],
        \ 'complete': l:ctx['complete'],
        \ 'subscribe': l:ctx['subscribe'],
        \ 'asObservable': l:ctx['asObservable'],
        \ }
endfunction

function! s:createSubjectNextFn(ctx, newValue) abort
    for l:observer in a:ctx['observers']
        if has_key(l:observer, 'next') | call l:observer['next'](a:newValue) | endif
    endfor
endfunction

function! s:createSubjectErrorFn(ctx, error) abort
    for l:observer in a:ctx['observers']
        if has_key(l:observer, 'error') | call l:observer['error'](a:error) | endif
    endfor
endfunction

function! s:createSubjectCompleteFn(ctx) abort
    for l:observer in a:ctx['observers']
        if has_key(l:observer, 'complete') | call l:observer['complete']() | endif
    endfor
endfunction

function! s:createSubjectUnsubscribeSubjectFn(ctx, observer) abort
    let l:i = -1
    let l:found = 0
    for l:observer in a:ctx['observers']
        let l:i += 1
        if l:observer == a:observer
            let l:found = 1
            break
        endif
    endfor
    if l:found
        call remove(a:ctx['observers'], l:i)
    endif
endfunction

function! s:createSubjectSubscribeSubjectFn(ctx, listener) abort
    let l:observer = type(a:listener) == s:func_type ? { 'next': a:listener } : a:listener
    call add(a:ctx['observers'], l:observer)
    return function('s:createSubjectSubscribeSubjectUnsubscribeFn', [a:ctx, l:observer])
endfunction

function! s:createSubjectSubscribeSubjectUnsubscribeFn(ctx, observer) abort
    call a:ctx['unsubscribe'](a:observer)
endfunction
" }}}

" createBehaviorSubject() {{{
function! lsp#callbag#createBehaviorSubject(initialValue) abort
    let l:ctx = { 'subject': lsp#callbag#createSubject(), 'lastValue': a:initialValue }
    let l:ctx['subscribe'] = function('s:createBehaviorSubjectSubscribeSubjectFn', [l:ctx])
    let l:ctx['subscribeSubjectNextFn'] = function('s:createBehaviorSubjectNextFn', [l:ctx])
    let l:ctx['asObservable'] = function('s:asObservable', [l:ctx])
    return {
        \ 'next': l:ctx['subscribeSubjectNextFn'],
        \ 'error': l:ctx['subject']['error'],
        \ 'complete': l:ctx['subject']['complete'],
        \ 'subscribe': l:ctx['subscribe'],
        \ 'asObservable': l:ctx['asObservable'],
        \ }
endfunction

function! s:createBehaviorSubjectSubscribeSubjectFn(ctx, listener) abort
    let l:observer = type(a:listener) == s:func_type ? { 'next': a:listener } : a:listener
    if has_key(l:observer, 'next') | call l:observer['next'](a:ctx['lastValue']) | endif
    return a:ctx['subject']['subscribe'](l:observer)
endfunction

function! s:createBehaviorSubjectNextFn(ctx, newValue) abort
    let a:ctx['lastValue'] = a:newValue
    call a:ctx['subject']['next'](a:newValue)
endfunction
" }}}

" ***** SOURCES ***** {{{

" createSource() {{{
function! lsp#callbag#createSource(fn) abort
    let l:ctx = { 'fn': a:fn }
    return function('s:createSourceFn', [l:ctx])
endfunction

function! s:createSourceFn(ctx, start, sink) abort
    let l:ctxCreateSource = { 'ctx': a:ctx, 'sink': a:sink }
    if a:start == 0
        let l:ctxCreateSource['finished'] = 0
        let l:observer = {
            \ 'next': function('s:createSourceFnNextFn', [l:ctxCreateSource]),
            \ 'error': function('s:createSourceFnErrorFn', [l:ctxCreateSource]),
            \ 'complete': function('s:createSourceFnCompleteFn', [l:ctxCreateSource]),
            \ }
        let l:ctxCreateSource['unsubscribe'] = a:ctx['fn'](l:observer)
        let l:ctxCreateSource['talkback'] = function('s:createSourceFnTalkbackFn', [l:ctxCreateSource])
        call a:sink(0, l:ctxCreateSource['talkback'])
    endif
endfunction

function! s:createSourceFnNextFn(ctxCreateSource, value) abort
    if a:ctxCreateSource['finished'] | return | endif
    call a:ctxCreateSource['sink'](1, a:value)
endfunction

function! s:createSourceFnErrorFn(ctxCreateSource, err) abort
    if a:ctxCreateSource['finished'] | return | endif
    let a:ctxCreateSource['finished'] = 1
    call a:ctxCreateSource['sink'](2, a:err)
endfunction

function! s:createSourceFnCompleteFn(ctxCreateSource) abort
    if a:ctxCreateSource['finished'] | return | endif
    let a:ctxCreateSource['finished'] = 1
    call a:ctxCreateSource['sink'](2, lsp#callbag#undefined())
endfunction

function! s:createSourceFnTalkbackFn(ctxCreateSource, t, d) abort
    if a:t == 2 && has_key(a:ctxCreateSource, 'unsubscribe') && type(a:ctxCreateSource['unsubscribe']) == s:func_type
        call a:ctxCreateSource['unsubscribe']()
    endif
endfunction
" }}}

" create() {{{
function! lsp#callbag#create(...) abort
    let l:ctx = {}
    if a:0 > 0
        let l:ctx['producer'] = a:1
    endif
    return lsp#callbag#createSource(function('s:createCreateSourceFn', [l:ctx]))
endfunction

function! s:createCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = { 'o': a:o }

    let l:ctxCreateSource['unsubscribe'] = a:ctx['producer'](
        \ function('s:createNextFn', [l:ctxCreateSource]),
        \ function('s:createErrorFn', [l:ctxCreateSource]),
        \ function('s:createCompleteFn', [l:ctxCreateSource]))
    return function('s:createDisposeFn', [l:ctxCreateSource])
endfunction

function! s:createNextFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['o']['next'](a:value)
endfunction

function! s:createErrorFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['o']['error'](a:value)
    if has_key(a:ctxCreateSource, 'unsubscribe')
        call a:ctxCreateSource['unsubscribe']()
        call remove(a:ctxCreateSource, 'unsubscribe')
    endif
endfunction

function! s:createCompleteFn(ctxCreateSource) abort
    call a:ctxCreateSource['o']['complete']()
    if has_key(a:ctxCreateSource, 'unsubscribe')
        call a:ctxCreateSource['unsubscribe']()
        call remove(a:ctxCreateSource, 'unsubscribe')
    endif
endfunction

function! s:createDisposeFn(ctxCreateSource) abort
    if has_key(a:ctxCreateSource, 'unsubscribe')
        call a:ctxCreateSource['unsubscribe']()
        call remove(a:ctxCreateSource, 'unsubscribe')
    endif
endfunction
" }}}

" empty() {{{
function! lsp#callbag#empty() abort
    return lsp#callbag#createSource(function('s:emptyCreateSourceFn'))
endfunction

function! s:emptyCreateSourceFn(o) abort
    call a:o['complete']()
endfunction
" }}}

" of() {{{
function! lsp#callbag#of(...) abort
    return lsp#callbag#fromList(a:000)
endfunction
" }}}

" fromEvent() {{{
let s:fromEventGroupNameIndex = 0
function! s:fromEventGenerateListenerGroupName() abort
    let s:fromEventGroupNameIndex = s:fromEventGroupNameIndex + 1
    return '__lsp__callbag_fromEvent_' . s:fromEventGroupNameIndex . '__'
endfunction

let s:fromEventHandlerCallbacks = {}
function! s:fromEventAddListener(events, callback, groupName) abort
    let s:fromEventHandlerCallbacks[a:groupName] = a:callback
    execute 'augroup ' . a:groupName
    execute 'autocmd!'
    let l:events = type(a:events) == type('') ? [a:events] : a:events
    for l:event in l:events
        let l:exec =  'call s:fromEventNotifyAddListenerHandler("' . a:groupName . '")'
        if type(l:event) == type('')
            execute 'au ' . l:event . ' * ' . l:exec
        else
            execute 'au ' . join(l:event, ' ') .' ' .  l:exec
        endif
    endfor
    execute 'augroup end'
    return function('s:fromEventRemoveListener', [a:groupName])
endfunction

function! s:fromEventRemoveListener(groupName) abort
    execute 'augroup ' a:groupName
    autocmd!
    execute 'augroup end'
    if has_key(s:fromEventHandlerCallbacks, a:groupName)
        call remove(s:fromEventHandlerCallbacks, a:groupName)
    endif
endfunction

function! s:fromEventNotifyAddListenerHandler(groupName) abort
    call s:fromEventHandlerCallbacks[a:groupName]()
endfunction

function! lsp#callbag#fromEvent(events, ...) abort
    let l:ctx = { 'events': a:events }
    if a:0 > 0
        let l:ctx['augroup'] = a:1
    else
        let l:ctx['augroup'] = s:fromEventGenerateListenerGroupName()
    endif
    return lsp#callbag#createSource(function('s:fromEventCreateSourceFn', [l:ctx]))
endfunction

function! s:fromEventCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = { 'ctx': a:ctx, 'o': a:o }

    let l:ctxCreateSource['unsubscribe'] = s:fromEventAddListener(a:ctx['events'], function('s:fromEventCreateSourceHandlerFn', [l:ctxCreateSource]), a:ctx['augroup'])

    return function('s:fromEventDisposeFn', [l:ctxCreateSource])
endfunction

function! s:fromEventCreateSourceHandlerFn(ctxCreateSource) abort
    call a:ctxCreateSource['o']['next'](lsp#callbag#undefined())
endfunction

function! s:fromEventDisposeFn(ctxCreateSource) abort
    execute 'augroup ' . a:ctxCreateSource['ctx']['augroup']
    autocmd!
    execute 'augroup end'
    if has_key(a:ctxCreateSource, 'unsubscribe')
        call a:ctxCreateSource['unsubscribe']()
    endif
endfunction
" }}}

" fromList() {{{
function! lsp#callbag#fromList(values) abort
    let l:ctx = { 'values': a:values }
    return lsp#callbag#createSource(function('s:fromListCreateSourceFn', [l:ctx]))
endfunction

function! s:fromListCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = { 'finished': 0 }

    for l:value in a:ctx['values']
        if l:ctxCreateSource['finished'] | break | endif
        call a:o['next'](l:value)
    endfor

    if !l:ctxCreateSource['finished']
        call a:o['complete']()
    endif

    return function('s:fromListDisposeFn', [l:ctxCreateSource])
endfunction

function! s:fromListDisposeFn(ctxCreateSource) abort
    let a:ctxCreateSource['finished'] = 1
endfunction
" }}}

" lazy() {{{
function! lsp#callbag#lazy(f) abort
    let l:ctx = { 'f': a:f }
    return lsp#callbag#createSource(function('s:lazyCreateSourceFn', [l:ctx]))
endfunction

function! s:lazyCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = { 'finished': 0 }
    call a:o['next'](a:ctx['f']())
    if !l:ctxCreateSource['finished'] | call a:o['complete']() | endif
    return function('s:lazyDisposeFn', [l:ctxCreateSource])
endfunction

function! s:lazyDisposeFn(ctxCreateSource) abort
    let a:ctxCreateSource['finished'] = 1
endfunction
" }}}

" never() {{{
function! lsp#callbag#never() abort
    return lsp#callbag#createSource(function('s:neverCreateSourceFn'))
endfunction

function! s:neverCreateSourceFn(o) abort
    " source that never completes and emits no data
endfunction
" }}}

" interval() {{{
function! lsp#callbag#interval(period) abort
    return lsp#callbag#timer(a:period, a:period)
endfunction
" }}}

" throwError() {{{
function! lsp#callbag#throwError(err) abort
    let l:ctx = { 'error': a:err }
    return lsp#callbag#createSource(function('s:throwErrorCreateSourceFn', [l:ctx]))
endfunction

function s:throwErrorCreateSourceFn(ctxCreateSource, o) abort
    if type(a:ctxCreateSource['error']) == s:func_type
        call a:o['error'](a:ctxCreateSource['error']())
    else
        call a:o['error'](a:ctxCreateSource['error'])
    endif
endfunction
" }}}

" timer() {{{
function! lsp#callbag#timer(initialDelay, ...) abort
    let l:ctx = { 'initialDelay': a:initialDelay }
    if a:0 == 1 | let l:ctx['period'] = a:1 | endif
    return lsp#callbag#createSource(function('s:timerCreateSourceFn', [l:ctx]))
endfunction

function! s:timerCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = { 'o': a:o, 'n': -1, 'ctx': a:ctx }

    let l:ctxCreateSource['initialDelayTimerId'] = timer_start(a:ctx['initialDelay'],
        \ function('s:timerInitialDelayTimerCb', [l:ctxCreateSource]))

    return function('s:timerDisposeFn', [l:ctxCreateSource])
endfunction

function! s:timerInitialDelayTimerCb(ctxCreateSource, ...) abort
    let a:ctxCreateSource['n'] += 1
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['n'])
    if has_key(a:ctxCreateSource['ctx'], 'period')
        let a:ctxCreateSource['periodTimerId'] = timer_start(a:ctxCreateSource['ctx']['period'],
            \ function('s:timerPeriodTimerCb', [a:ctxCreateSource]), { 'repeat': -1 })
    else
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction

function! s:timerPeriodTimerCb(ctxCreateSource, ...) abort
    let a:ctxCreateSource['n'] += 1
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['n'])
endfunction

function! s:timerDisposeFn(ctxCreateSource) abort
    call timer_stop(a:ctxCreateSource['initialDelayTimerId'])
    if has_key(a:ctxCreateSource['ctx'], 'period') && has_key(a:ctxCreateSource, 'periodTimerId')
        call timer_stop(a:ctxCreateSource['periodTimerId'])
    endif
endfunction
" }}}

" ***** OPERATORS ***** {{{

" debounceTime() {{{
function! lsp#callbag#debounceTime(dueTime) abort
    let l:ctx = { 'dueTime': a:dueTime }
    return function('s:debounceTimeFn', [l:ctx])
endfunction

function! s:debounceTimeFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:debounceTimeCreateSource', [l:ctxSource]))
endfunction

function! s:debounceTimeCreateSource(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o }

    let l:observer = {
        \ 'next': function('s:debounceNextFn', [l:ctxCreateSource]),
        \ 'error': function('s:debounceErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:debounceCompleteFn', [l:ctxCreateSource]),
        \ }

    let l:ctxCreateSource['unsubscribe'] = lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])

    return function('s:debounceTimeDisposeFn', [l:ctxCreateSource])
endfunction

function! s:debounceNextFn(ctxCreateSource, value) abort
    if has_key(a:ctxCreateSource, 'timerId') | call timer_stop(a:ctxCreateSource['timerId']) | endif
    let a:ctxCreateSource['lastValue'] = a:value

    let a:ctxCreateSource['timerId'] = timer_start(a:ctxCreateSource['ctxSource']['ctx']['dueTime'], function('s:debounceTimeTimerCb', [a:ctxCreateSource]))
endfunction

function! s:debounceTimeTimerCb(ctxCreateSource, ...) abort
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['lastValue'])
endfunction

function! s:debounceErrorFn(ctxCreateSource, err) abort
    if has_key(a:ctxCreateSource, 'timerId') | call timer_stop(a:ctxCreateSource['timerId']) | endif
    call a:ctxCreateSource['o']['error'](a:err)
endfunction

function! s:debounceCompleteFn(ctxCreateSource) abort
    if has_key(a:ctxCreateSource, 'timerId') | call timer_stop(a:ctxCreateSource['timerId']) | endif
    call a:ctxCreateSource['o']['complete']()
endfunction

function! s:debounceTimeDisposeFn(ctxCreateSource) abort
    if has_key(a:ctxCreateSource, 'timerId')
        call timer_stop(a:ctxCreateSource['timerId'])
        call remove(a:ctxCreateSource, 'timerId')
    endif
    call l:ctxCreateSource('unsubscribe')()
endfunction
" }}}

" distinctUntilChanged() {{{
function! lsp#callbag#distinctUntilChanged(...) abort
    let l:ctx = { 'comparator': a:0 == 0 ? function('s:distinctUntilChangedDefaultComparator') : a:1 }
    return function('s:distinctUntilChangedFn', [l:ctx])
endfunction

function! s:distinctUntilChangedFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:distinctUntilChangedCreateSourceFn', [l:ctxSource]))
endfunction

function! s:distinctUntilChangedCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o, 'first': 1 }
    let l:observer = {
        \ 'next': function('s:distinctUntilChangedNextFn', [l:ctxCreateSource]),
        \ 'error': a:o['error'],
        \ 'complete': a:o['complete'],
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:distinctUntilChangedNextFn(ctxCreateSource, value) abort
    if a:ctxCreateSource['first'] || !a:ctxCreateSource['ctxSource']['ctx']['comparator'](a:ctxCreateSource['previous'], a:value)
        let a:ctxCreateSource['first'] = 0
        let a:ctxCreateSource['previous'] = a:value
        call a:ctxCreateSource['o']['next'](a:value)
    endif
endfunction

function! s:distinctUntilChangedDefaultComparator(a, b) abort
    return a:a == a:b
endfunction
" }}}

" filter() {{{
function! lsp#callbag#filter(predicate) abort
    let l:ctx = { 'predicate': a:predicate }
    return function('s:filterFn', [l:ctx])
endfunction

function! s:filterFn(ctx, source) abort
    let l:ctxSource = { 'source': a:source, 'ctx': a:ctx }
    return lsp#callbag#createSource(function('s:filterCreateSourceFn', [l:ctxSource]))
endfunction

function! s:filterCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'o': a:o, 'ctxSource': a:ctxSource }
    let l:observer = {
        \ 'next': function('s:filterNextFn', [l:ctxCreateSource]),
        \ 'error': a:o.error,
        \ 'complete': a:o.complete,
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:filterNextFn(ctxCreateSource, value) abort
    if a:ctxCreateSource['ctxSource']['ctx']['predicate'](a:value)
        call a:ctxCreateSource['o']['next'](a:value)
    endif
endfunction
" }}}

" flatMap() {{{
function! lsp#callbag#flatMap(mapper) abort
    let l:ctx = { 'mapper': a:mapper }
    return function('s:flatMapFn', [l:ctx])
endfunction

function! s:flatMapFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
     return lsp#callbag#createSource(function('s:flatMapCreateSourceFn', [l:ctxSource]))
endfunction

function! s:flatMapCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = {
        \ 'ctxSource': a:ctxSource,
        \ 'o': a:o,
        \ 'finished': 0,
        \ 'subscriptionList': [],
        \ }
    let l:ctxCreateSource['cancelSubscriptions'] = function('s:flatMapCancelSubscriptionsFn', [l:ctxCreateSource])
    let l:ctxCreateSource['removeSubscription'] = function('s:flatMapRemoveSubscriptionFn', [l:ctxCreateSource])

    let l:observer = {
        \ 'next': function('s:flatMapNextFn', [l:ctxCreateSource]),
        \ 'error': function('s:flatMapErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:flatMapCompleteFn', [l:ctxCreateSource]),
        \ }

    let l:ctxCreateSource['unsubscribe'] = lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])

    return function('s:flatMapDispose', [l:ctxCreateSource])
endfunction

function! s:flatMapCancelSubscriptionsFn(ctxCreateSource) abort
    for l:subscription in a:ctxCreateSource['subscriptionList']
        if has_key(l:subscription, 'unsubscribe')
            call l:subscription['unsubscribe']()
        endif
    endfor
endfunction

function! s:flatMapRemoveSubscriptionFn(ctxCreateSource, subscription) abort
    let l:i = 0
    let l:len = len(a:ctxCreateSource['subscriptionList'])
    while l:i < l:len
        let l:subscription = a:ctxCreateSource['subscriptionList'][l:i]
        if l:subscription == a:subscription
            call remove(a:ctxCreateSource['subscriptionList'], l:i)
            break
        endif
        let l:i += 1
    endwhile
endfunction

function! s:flatMapErrorFn(ctxCreateSource, err) abort
    let a:ctxCreateSource['finished'] = 1
    call a:ctxCreateSource['cancelSubscriptions']()
    call a:ctxCreateSource['o']['error'](a:err)
endfunction

function! s:flatMapCompleteFn(ctxCreateSource) abort
    let a:ctxCreateSource['finished'] = 1
    if empty(a:ctxCreateSource['subscriptionList'])
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction

function! s:flatMapDispose(ctxCreateSource) abort
    call a:ctxCreateSource['cancelSubscriptions']()
    call a:ctxCreateSource['unsubscribe']()
endfunction

function! s:flatMapNextFn(ctxCreateSource, value) abort
    if !a:ctxCreateSource['finished']
        let l:mappedCtx = {}
        let l:mappedCtx['subscription'] = {}
        call add(a:ctxCreateSource['subscriptionList'], l:mappedCtx['subscription'])
        let l:mappedObserver = {
            \ 'next': function('s:flatMapMappedNextFn', [a:ctxCreateSource, l:mappedCtx]),
            \ 'error': function('s:flatMapMappedErrorFn', [a:ctxCreateSource, l:mappedCtx]),
            \ 'complete': function('s:flatMapMappedCompleteFn', [a:ctxCreateSource, l:mappedCtx]),
            \ }

        let l:Source = a:ctxCreateSource['ctxSource']['ctx']['mapper'](a:value)
        let l:mappedCtx['subscription']['unsubscribe'] = lsp#callbag#subscribe(l:mappedObserver)(l:Source)
    endif
endfunction

function! s:flatMapMappedNextFn(ctxCreateSource, mappedCtx, value) abort
    call a:ctxCreateSource['o']['next'](a:value)
endfunction

function! s:flatMapMappedErrorFn(ctxCreateSource, mappedCtx, err) abort
    call a:ctxCreateSource['removeSubscription'](a:mappedCtx['subscription'])
    call a:ctxCreateSource['cancelSubscriptions']()
    call a:ctxCreateSource['o']['error'](a:err)
    call a:ctxCreateSource['unsubscribe']()
endfunction

function! s:flatMapMappedCompleteFn(ctxCreateSource, mappedCtx) abort
    call a:ctxCreateSource['removeSubscription'](a:mappedCtx['subscription'])
    if a:ctxCreateSource['finished'] && empty(a:ctxCreateSource['subscriptionList'])
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction
" }}}

" map() {{{
function! lsp#callbag#map(mapper) abort
    let l:ctx = { 'mapper': a:mapper }
    return function('s:mapFn', [l:ctx])
endfunction

function! s:mapFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:mapCreateSourceFn', [l:ctxSource]))
endfunction

function! s:mapCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o }
    let l:observer = {
        \ 'next': function('s:mapNextFn', [l:ctxCreateSource]),
        \ 'error': a:o.error,
        \ 'complete': a:o.complete,
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:mapNextFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['ctxSource']['ctx']['mapper'](a:value))
endfunction
" }}}

" mapTo() {{{
function! lsp#callbag#mapTo(value) abort
    return lsp#callbag#map(function('s:mapToFn', [a:value]))
endfunction

function! s:mapToFn(value, ...) abort
    return a:value
endfunction
" }}}

" materialize() {{{
function! lsp#callbag#materialize() abort
    return function('s:materializeFn')
endfunction

function! s:materializeFn(source) abort
    let l:ctxSource = { 'source': a:source }
    return lsp#callbag#createSource(function('s:materializeCreateSource', [l:ctxSource]))
endfunction

function! s:materializeCreateSource(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o }
    let l:observer = {
        \ 'next': function('s:materializeNextFn', [l:ctxCreateSource]),
        \ 'error': function('s:materializeErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:materializeCompleteFn', [l:ctxCreateSource]),
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:materializeNextFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['o']['next'](lsp#callbag#createNextNotification(a:value))
endfunction

function! s:materializeErrorFn(ctxCreateSource, err) abort
    call a:ctxCreateSource['o']['next'](lsp#callbag#createErrorNotification(a:err))
    call a:ctxCreateSource['o']['complete']()
endfunction

function! s:materializeCompleteFn(ctxCreateSource) abort
    call a:ctxCreateSource['o']['next'](lsp#callbag#createCompleteNotification())
    call a:ctxCreateSource['o']['complete']()
endfunction
" }}}

" mergePool() {{{
function! lsp#callbag#mergePool(sources, size) abort
    let l:ctx = { 'sources': a:sources }
    let l:ctx['size'] = a:size == -1 ? len(a:sources) : a:size " -1 for all parallel
    return lsp#callbag#createSource(function('s:mergePoolCreateSourceFn', [l:ctx]))
endfunction

function! s:mergePoolCreateSourceFn(ctx, o) abort
    let l:ctxCreateSource = {
        \ 'ctx': a:ctx,
        \ 'o': a:o,
        \ 'nbSources': len(a:ctx['sources']),
        \ 'nbStarted': 0,
        \ 'nbFinished': 0,
        \ 'finished': 0,
        \ 'unsubscribeFuncs': [],
        \ }
    for l:I in a:ctx['sources']
        call add(l:ctxCreateSource['unsubscribeFuncs'], function('s:noop'))
    endfor

    let l:ctxCreateSource['handleComplete'] = function('s:mergePoolHandleCompleteFn', [l:ctxCreateSource])
    let l:ctxCreateSource['startSource'] = function('s:mergePoolStartSourceFn', [l:ctxCreateSource])

    let l:nbToStart = min([l:ctxCreateSource['nbSources'], a:ctx['size']])
    while l:ctxCreateSource['nbStarted'] < l:nbToStart
        call l:ctxCreateSource['startSource'](l:ctxCreateSource['nbStarted'])
    endwhile

    return function('s:mergePoolUnsubscribeFn', [l:ctxCreateSource])
endfunction

function! s:mergePoolHandleCompleteFn(ctxCreateSource) abort
    let a:ctxCreateSource['nbFinished'] += 1
    let a:ctxCreateSource['finished'] = a:ctxCreateSource['finished'] || a:ctxCreateSource['nbFinished'] == a:ctxCreateSource['nbSources']
    if a:ctxCreateSource['finished']
        call a:ctxCreateSource['o']['complete']()
    elseif a:ctxCreateSource['nbStarted'] < a:ctxCreateSource['nbSources']
        " start sources which hasn't started
        call a:ctxCreateSource['startSource'](a:ctxCreateSource['nbStarted'])
    endif
    " all sources have started but some haven't finished
endfunction

function! s:mergePoolStartSourceFn(ctxCreateSource, index) abort
    let a:ctxCreateSource['nbStarted'] += 1
    let l:ctxStartSource = { 'ctxCreateSource': a:ctxCreateSource, 'index': a:index }
    let a:ctxCreateSource['unsubscribeFuncs'][a:index] = lsp#callbag#subscribe({
        \ 'next': a:ctxCreateSource['o'].next,
        \ 'error': function('s:mergePoolStartSourceHandleErrorFn', [l:ctxStartSource]),
        \ 'complete': a:ctxCreateSource['handleComplete'],
        \ })(a:ctxCreateSource['ctx']['sources'][a:index])
endfunction

function! s:mergePoolStartSourceHandleErrorFn(ctxStartSource, error) abort
    let a:ctxStartSource['ctxCreateSource']['finished'] = 1

    let l:j = 0
    while l:j < a:ctxStartSource['ctxCreateSource']['nbSources']
        if l:j != a:ctxStartSource['index']
            " if lsp#callbag fail we unsubscribe other sources
            let l:UnsubscribeFun = get(a:ctxStartSource['ctxCreateSource']['unsubscribeFuncs'], l:j, function('s:noop'))
            call l:UnsubscribeFun()
        endif
        let l:j += 1
    endwhile

    call a:ctxStartSource['ctxCreateSource'].o.error(a:error)
endfunction

function! s:mergePoolUnsubscribeFn(ctxCreateSource) abort
    let a:ctxCreateSource['finished'] = 1
    let l:i = 0
    while l:i < a:ctxCreateSource['nbSources']
        let l:unsubscribeFunc = get(a:ctxCreateSource['unsubscribeFuncs'], l:i, function('s:noop'))
        call l:unsubscribeFunc()
        let l:i += 1
    endwhile
endfunction
" }}}

" merge() {{{
function! lsp#callbag#merge(...) abort
    return lsp#callbag#mergePool(a:000, a:0)
endfunction
" }}}

" scan() {{{
function! lsp#callbag#scan(reducer, seed) abort
    let l:ctx = { 'reducer': a:reducer, 'seed': a:seed }
    return function('s:scanFn', [l:ctx])
endfunction

function! s:scanFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:scanCreateSourceFn', [l:ctxSource]))
endfunction

function! s:scanCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o,
        \ 'acc': a:ctxSource['ctx']['seed'] }
    let l:observer = {
        \ 'next': function('s:scanNextFn', [l:ctxCreateSource]),
        \ 'error': a:o.error,
        \ 'complete': a:o.complete,
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:scanNextFn(ctxCreateSource, value) abort
    let a:ctxCreateSource['acc'] = a:ctxCreateSource['ctxSource']['ctx']['reducer'](a:ctxCreateSource['acc'], a:value)
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['acc'])
endfunction
" }}}

" switchMap() {{{
function! lsp#callbag#switchMap(mapper) abort
    let l:ctx = { 'mapper': a:mapper }
    return function('s:switchMapFn', [l:ctx])
endfunction

function! s:switchMapFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:switchMapCreateSourceFn', [l:ctxSource]))
endfunction

function! s:switchMapCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = {
        \ 'ctxSource': a:ctxSource,
        \ 'o': a:o,
        \ 'hasCurrentSubscription': 0,
        \ 'completed': 0,
        \ 'finished': 0,
        \ 'unsubscribe': function('s:noop'),
        \ 'unsubscribePrevious': function('s:noop')
        \  }
    let l:ctxCreateSource['mappedObserver'] = {
        \ 'next': a:o['next'],
        \ 'error': function('s:switchMapMappedObserverErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:switchMapMappedObserverCompleteFn', [l:ctxCreateSource]),
        \ }
    let l:observer = {
        \ 'next': function('s:switchMapObserverNextFn', [l:ctxCreateSource]),
        \ 'error': function('s:switchMapObserverErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:switchMapObserverCompleteFn', [l:ctxCreateSource]),
        \ }
    let l:ctxCreateSource['unsubscribe'] = lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
    return function('s:switchMapDisposeFn', [l:ctxCreateSource])
endfunction

function! s:switchMapMappedObserverErrorFn(ctxCreateSource, err) abort
    let a:ctxCreateSource['hasCurrentSubscription'] = 0
    let a:ctxCreateSource['finished'] = 1
    call a:ctxCreateSource['o']['error'](a:err)
    call a:ctxCreateSource['unsubscribe']()
endfunction

function! s:switchMapMappedObserverCompleteFn(ctxCreateSource) abort
    let a:ctxCreateSource['hasCurrentSubscription'] = 0
    if a:ctxCreateSource['completed'] && !a:ctxCreateSource['finished']
        let a:ctxCreateSource['finished'] = 1
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction

function! s:switchMapObserverNextFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['unsubscribePrevious']()
    let a:ctxCreateSource['hasCurrentSubscription'] = 1
    let l:Source = a:ctxCreateSource['ctxSource']['ctx']['mapper'](a:value)
    let a:ctxCreateSource['unsubscribePrevious'] = lsp#callbag#subscribe(a:ctxCreateSource['mappedObserver'])(l:Source)
endfunction

function! s:switchMapObserverErrorFn(ctxCreateSource, err) abort
    let a:ctxCreateSource['completed'] = 1
    let a:ctxCreateSource['finished'] = 1
    call a:ctxCreateSource['unsubscribePrevious']()
    call a:ctxCreateSource['o']['error'](a:err)
endfunction

function! s:switchMapObserverCompleteFn(ctxCreateSource) abort
    let a:ctxCreateSource['completed'] = 1
    if !a:ctxCreateSource['hasCurrentSubscription'] && !a:ctxCreateSource['finished']
        let a:ctxCreateSource['finished'] = 1
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction

function! s:switchMapDisposeFn(ctxCreateSource) abort
    call a:ctxCreateSource['unsubscribePrevious']()
    call a:ctxCreateSource['unsubscribe']()
endfunction
" }}}

" share() {{{
function! lsp#callbag#share() abort
    let l:ctx = {}
    return function('s:shareFn', [l:ctx])
endfunction

function! s:shareFn(ctx, source) abort
    let l:ctxSource = {
        \ 'ctx': a:ctx,
        \ 'source': a:source,
        \ 'observers': [],
        \ 'isRunning': 0,
        \ }
    return lsp#callbag#createSource(function('s:shareCreateSourceFn', [l:ctxSource]))
endfunction

function! s:shareCreateSourceFn(ctxSource, o) abort
    call add(a:ctxSource['observers'], a:o)

    if !a:ctxSource['isRunning']
        let a:ctxSource['isRunning'] = 1
        let l:observer = {
            \ 'next': function('s:shareNextFn', [a:ctxSource]),
            \ 'error': function('s:shareErrorFn', [a:ctxSource]),
            \ 'complete': function('s:shareCompleteFn', [a:ctxSource]),
            \ }
        call lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
    endif

    return function('s:shareDisposeFn', [a:ctxSource, a:o])
endfunction

function! s:shareNextFn(ctxSource, value) abort
    for l:observer in a:ctxSource['observers']
        call l:observer['next'](a:value)
    endfor
endfunction

function! s:shareErrorFn(ctxSource, err) abort
    for l:observer in a:ctxSource['observers']
        call l:observer['error'](a:err)
    endfor
endfunction

function! s:shareCompleteFn(ctxSource) abort
    for l:observer in a:ctxSource['observers']
        call l:observer['complete']()
    endfor
endfunction

function! s:shareDisposeFn(ctxSource, o) abort
    let l:i = 0
    let l:len = len(a:ctxSource['observers'])
    while l:i < l:len
        let l:observer = a:ctxSource['observers'][l:i]
        if l:observer == a:o
            call remove(a:ctxSource['observers'], l:i)
            break
        endif
        let l:i += 1
    endwhile
    if len(a:ctxSource['observers']) == 0 && has_key(a:ctxSource, 'unsubscribe')
      call a:ctxSource['unsubscribe']()
    endif
endfunction
" }}}

" reduce() {{{
function! lsp#callbag#reduce(reducer, seed) abort
    let l:ctx = { 'reducer': a:reducer, 'seed': a:seed }
    return function('s:reduceFn', [l:ctx])
endfunction

function! s:reduceFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:reduceCreateSourceFn', [l:ctxSource]))
endfunction

function! s:reduceCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o,
        \ 'acc': a:ctxSource['ctx']['seed'] }
    let l:observer = {
        \ 'next': function('s:reduceNextFn', [l:ctxCreateSource]),
        \ 'error': a:o.error,
        \ 'complete': function('s:reduceCompleteFn', [l:ctxCreateSource])
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:reduceNextFn(ctxCreateSource, value) abort
    let a:ctxCreateSource['acc'] = a:ctxCreateSource['ctxSource']['ctx']['reducer'](a:ctxCreateSource['acc'], a:value)
endfunction

function! s:reduceCompleteFn(ctxCreateSource) abort
    call a:ctxCreateSource['o']['next'](a:ctxCreateSource['acc'])
    call a:ctxCreateSource['o']['complete']()
endfunction
" }}}

" take() {{{
function! lsp#callbag#take(count) abort
    let l:ctx = { 'count': a:count }
    return function('s:takeSource', [l:ctx])
endfunction

function! s:takeSource(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:takeCreateSource', [l:ctxSource]))
endfunction

function! s:takeCreateSource(ctxSource, o) abort
    if a:ctxSource['ctx']['count'] <= 0
        call a:o['complete']()
        return
    endif

    let l:ctxCreateSource = {
        \ 'ctxSource': a:ctxSource,
        \ 'o': a:o,
        \ 'taken': 0,
        \ 'unsubscribe': function('s:noop')
        \ }

    let l:observer = {
        \   'next': function('s:takeNextFn', [l:ctxCreateSource]),
        \   'error': a:o['error'],
        \   'complete': a:o['complete'],
        \ }

    let l:ctxCreateSource['unsubscribe'] = lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])

    return l:ctxCreateSource['unsubscribe']
endfunction

function! s:takeNextFn(ctxCreateSource, value) abort
    call a:ctxCreateSource['o']['next'](a:value)
    let a:ctxCreateSource['taken'] += 1

    if a:ctxCreateSource['taken'] >= a:ctxCreateSource['ctxSource']['ctx']['count']
        call a:ctxCreateSource['unsubscribe']()
        call a:ctxCreateSource['o']['complete']()
    endif
endfunction
" }}}

" takeUntil() {{{
function! lsp#callbag#takeUntil(notifier) abort
    let l:ctx = { 'notifier': a:notifier }
    return function('s:takeUntilFn', [l:ctx])
endfunction

function! s:takeUntilFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:takeUntilCreateSource', [l:ctxSource]))
endfunction

function! s:takeUntilCreateSource(ctxSource, o) abort
    let l:ctxTakeUntilCreateSource = {
        \ 'ctxSource': a:ctxSource,
        \ 'o': a:o,
        \ }

    let l:ctxTakeUntilCreateSource['sourceSubscription'] = lsp#callbag#subscribe({
        \ 'next': a:o['next'],
        \ 'error': a:o['error'],
        \ 'complete': a:o['complete'],
        \ })(a:ctxSource['source'])

    let l:ctxTakeUntilCreateSource['notifierSubscription'] = lsp#callbag#subscribe({
        \ 'next': function('s:takeUntilNotifierNextFn', [l:ctxTakeUntilCreateSource]),
        \ 'error': a:o['error'],
        \ 'complete': a:o['complete'],
        \ })(a:ctxSource['ctx']['notifier'])

    return function('s:takeUntilDisposeFn', [l:ctxTakeUntilCreateSource])
endfunction

function! s:takeUntilDisposeFn(ctxTakeUntilCreateSource) abort
    call a:ctxTakeUntilCreateSource['sourceSubscription']()
    call a:ctxTakeUntilCreateSource['notifierSubscription']()
endfunction

function! s:takeUntilNotifierNextFn(ctxTakeUntilCreateSource, value) abort
    call a:ctxTakeUntilCreateSource['o']['complete']()
endfunction
" }}}

" tap {{{
function! lsp#callbag#tap(...) abort
    let l:ctx = {}
    if a:0 > 0 && type(a:1) == type({}) " a:1 { next, error, complete }
        if has_key(a:1, 'next') | let l:ctx['next'] = a:1['next'] | endif
        if has_key(a:1, 'error') | let l:ctx['error'] = a:1['error'] | endif
        if has_key(a:1, 'complete') | let l:ctx['complete'] = a:1['complete'] | endif
    else " a:1 = next, a:2 = error, a:3 = complete
        if a:0 >= 1 | let l:ctx['next'] = a:1 | endif
        if a:0 >= 2 | let l:ctx['error'] = a:2 | endif
        if a:0 >= 3 | let l:ctx['complete'] = a:3 | endif
    endif
    return function('s:tapFn', [l:ctx])
endfunction

function! s:tapFn(ctx, source) abort
    let l:ctxSource = { 'ctx': a:ctx, 'source': a:source }
    return lsp#callbag#createSource(function('s:tapCreateSourceFn', [l:ctxSource]))
endfunction

function! s:tapCreateSourceFn(ctxSource, o) abort
    let l:ctxCreateSource = { 'ctxSource': a:ctxSource, 'o': a:o }
    let l:observer = {
        \ 'next': function('s:tapNextFn', [l:ctxCreateSource]),
        \ 'error': function('s:tapErrorFn', [l:ctxCreateSource]),
        \ 'complete': function('s:tapCompleteFn', [l:ctxCreateSource]),
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:tapNextFn(ctxCreateSource, value) abort
    if has_key(a:ctxCreateSource['ctxSource']['ctx'], 'next') | call a:ctxCreateSource['ctxSource']['ctx']['next'](a:value) | endif
    call a:ctxCreateSource['o']['next'](a:value)
endfunction

function! s:tapErrorFn(ctxCreateSource, err) abort
    if has_key(a:ctxCreateSource['ctxSource']['ctx'], 'error') | call a:ctxCreateSource['ctxSource']['ctx']['error'](a:err) | endif
    call a:ctxCreateSource['o']['error'](a:err)
endfunction

function! s:tapCompleteFn(ctxCreateSource) abort
    if has_key(a:ctxCreateSource['ctxSource']['ctx'], 'complete') | call a:ctxCreateSource['ctxSource']['ctx']['complete']() | endif
    call a:ctxCreateSource['o']['complete']()
endfunction
" }}}

" toList() {{{
function! lsp#callbag#toList() abort
    return function('s:toListFn')
endfunction

function! s:toListFn(source) abort
    let l:ctxSource = { 'source': a:source }
    return lsp#callbag#createSource(function('s:toListCreateSourceFn', [l:ctxSource]))
endfunction

function! s:toListCreateSourceFn(ctxSource, o) abort
    let l:ctxCreate = { 'o': a:o, 'values': [] }
    let l:observer = {
        \ 'next': function('s:toListNextFn', [l:ctxCreate]),
        \ 'error': a:o['error'],
        \ 'complete': function('s:toListCompleteFn', [l:ctxCreate]),
        \ }
    return lsp#callbag#subscribe(l:observer)(a:ctxSource['source'])
endfunction

function! s:toListNextFn(ctxCreate, value) abort
    call add(a:ctxCreate['values'], a:value)
endfunction

function! s:toListCompleteFn(ctxCreate) abort
    call a:ctxCreate['o']['next'](a:ctxCreate['values'])
    call a:ctxCreate['o']['complete']()
endfunction
" }}}

" toBlockingList() {{{
function! lsp#callbag#toBlockingList() abort
    return function('s:toBlockingListFn')
endfunction

function! s:toBlockingListFn(source) abort
    let l:ctxSource = { 'source': a:source,
        \ 'done': 0, 'items': [], 'unsubscribed': 0 }
    let l:ctxSource['unsubscribe'] = lsp#callbag#subscribe(
        \ function('s:toBlockingListNextFn', [l:ctxSource]),
        \ function('s:toBlockingListErrorFn', [l:ctxSource]),
        \ function('s:toBlockingListCompleteFn', [l:ctxSource]),
        \ )(a:source)
    if l:ctxSource['done'] | call s:toBlockingListUnsubscribe(l:ctxSource) | endif
    return {
        \   'unsubscribe': function('s:toBlockingListUnsubscribe', [l:ctxSource]),
        \   'wait': function('s:toBlockingListWait', [l:ctxSource])
        \ }
endfunction

function! s:toBlockingListUnsubscribe(ctxSource) abort
    if !has_key(a:ctxSource, 'unsubscribe') | return | endif
    if !a:ctxSource['unsubscribed']
        let a:ctxSource['unsubscribed'] = 1
        call a:ctxSource['unsubscribe']()
        if !a:ctxSource['done']
            let a:ctxSource['done'] = 1
        endif
    endif
endfunction

function! s:toBlockingListNextFn(ctxSource, value) abort
    call add(a:ctxSource['items'], a:value)
endfunction

function! s:toBlockingListErrorFn(ctxSource, err) abort
    let a:ctxSource['done'] = 1
    let a:ctxSource['error'] = a:err
endfunction

function! s:toBlockingListCompleteFn(ctxSource) abort
    let a:ctxSource['done'] = 1
    call s:toBlockingListUnsubscribe(a:ctxSource)
endfunction

function! s:toBlockingListWait(ctxSource, ...) abort
    if a:ctxSource['done']
        if has_key(a:ctxSource, 'error')
            throw a:ctxSource['error']
        else
            return a:ctxSource['items']
        endif
    else
        let l:opt = a:0 > 0 ? copy(a:1) : {}
        let l:opt['timedout'] = 0
        let l:opt['sleep'] = get(l:opt, 'sleep', 1)
        let l:opt['timeout'] = get(l:opt, 'timeout', -1)

        if l:opt['timeout'] > -1
            let l:opt['timer'] = timer_start(l:opt['timeout'], function('s:toBlockingListTimeoutCallback', [l:opt]))
        endif

        while !a:ctxSource['done'] && !l:opt['timedout']
            exec 'sleep ' . l:opt['sleep'] . 'm'
        endwhile

        if has_key(l:opt, 'timer')
            silent! call timer_stop(l:opt['timer'])
        endif

        call s:toBlockingListUnsubscribe(a:ctxSource)

        if l:opt['timedout']
            throw 'lsp#callbag toBlockingList().wait() timedout.'
        endif

        if has_key(a:ctxSource, 'error')
            throw a:ctxSource['error']
        else
            return a:ctxSource['items']
        endif
    endif
endfunction

function! s:toBlockingListTimeoutCallback(opt, ...) abort
    let a:opt['timedout'] = 1
endfunction
" }}}

" }}}

" spawn {{{
" let s:stdin = lsp#callbag#createSubject()
" call lsp#callbag#spawn(['bash', '-c', 'read i; echo $i'], {
"   \ 'stdin': s:stdin.asObservable(),
"   \ 'stdout': 0,
"   \ 'stderr': 0,
"   \ 'exit': 0,
"   \ 'start': 0, " notify when job starts before subscribing to stdin
"   \ 'ready': 0, " notiy when job starts and after subscribing to stdin
"   \ 'pid': 0,
"   \ 'failOnNonZeroExitCode': 1,
"   \ 'failOnStdinError': 1,
"   \ 'normalize': 'raw' | 'string' | 'array', (defaults to raw),
"   \ 'env': {},
"   \ })
"   call s:stdin.next('hi')
"   call s:stdin.complete() " required to close stdin
function! lsp#callbag#spawn(cmd, ...) abort
    let l:ctx = { 'cmd': a:cmd, 'opt': a:0 > 0 ? copy(a:000[0]) : {} }
    return lsp#callbag#create(function('s:spawnCreate', [l:ctx]))
endfunction

function! s:spawnCreate(ctx, next, error, complete) abort
    let l:ctxCreate = { 'ctx': a:ctx, 'next': a:next, 'error': a:error, 'complete': a:complete }
    let l:ctxCreate['state'] = {}
    let l:ctxCreate['dispose'] = 0
    let l:ctxCreate['exit'] = 0
    let l:ctxCreate['close'] = 0

    let l:normalize = get(a:ctx['opt'], 'normalize', 'raw')

    if has('nvim')
        let l:ctxCreate['jobopt'] = {
            \ 'on_exit': function('s:spawnNeovimOnExit', [l:ctxCreate]),
            \ }
        if l:normalize ==# 'string'
            let l:ctxCreate['normalize'] = function('s:spawnNormalizeNeovimString')
        else
            let l:ctxCreate['normalize'] = function('s:spawnNormalizeRaw')
        endif
        if get(a:ctx['opt'], 'stdout', 0) | let l:ctxCreate['jobopt']['on_stdout'] = function('s:spawnNeovimOnStdout', [l:ctxCreate]) | endif
        if get(a:ctx['opt'], 'stderr', 0) | let l:ctxCreate['jobopt']['on_stderr'] = function('s:spawnNeovimOnStderr', [l:ctxCreate]) | endif
        if has_key(a:ctx['opt'], 'env') | let l:ctxCreate['jobopt']['env'] = a:ctx['opt']['env'] | endif
        let l:ctxCreate['jobid'] = jobstart(a:ctx['cmd'], l:ctxCreate['jobopt'])
    else
        let l:ctxCreate['jobopt'] = {
            \ 'exit_cb': function('s:spawnVimExitCb', [l:ctxCreate]),
            \ 'close_cb': function('s:spawnVimCloseCb', [l:ctxCreate]),
            \ }
        if get(a:ctx['opt'], 'stdout', 0) | let l:ctxCreate['jobopt']['out_cb'] = function('s:spawnVimOutCb', [l:ctxCreate]) | endif
        if get(a:ctx['opt'], 'stderr', 0) | let l:ctxCreate['jobopt']['err_cb'] = function('s:spawnVimErrCb', [l:ctxCreate]) | endif
        if has_key(a:ctx['opt'], 'env') | let l:ctxCreate['jobopt']['env'] = a:ctx['opt']['env'] | endif
        if l:normalize ==# 'array'
            let l:ctxCreate['normalize'] = function('s:spawnNormalizeVimArray')
        else
            let l:ctxCreate['normalize'] = function('s:spawnNormalizeRaw')
        endif
        if has('patch-8.1.350') | let l:ctxCreate['jobopt']['noblock'] = 1 | endif
        let l:ctxCreate['stdinBuffer'] = ''
        let l:ctxCreate['job'] = job_start(a:ctx['cmd'], l:ctxCreate['jobopt'])
        let l:ctxCreate['jobchannel'] = job_getchannel(l:ctxCreate['job'])
        let l:ctxCreate['jobid'] = ch_info(l:ctxCreate['jobchannel'])['id']
    endif

    if l:ctxCreate['jobid'] < 0 | return | endif " jobstart failed. on_exit will notify with error

    let l:startData = {}
    if get(a:ctx['opt'], 'pid', 0)
        if has('nvim')
            let l:ctxCreate['pid'] = jobpid(l:ctxCreate['jobid'])
            let l:startData['pid'] = l:ctxCreate['pid']
        else
            let l:jobinfo = job_info(a:ctxCreate['job'])
            if type(l:jobinfo) == type({}) && has_key(l:jobinfo, 'process')
                let l:ctxCreate['pid'] = l:jobinfo['process']
                let l:startData['pid'] = l:ctxCreate['pid']
            endif
        endif
    endif

    if get(a:ctx['opt'], 'start', 0)
        let l:startData = { 'id': l:ctxCreate['jobid'], 'state': l:ctxCreate['state'] }
        call a:next({ 'event': 'start', 'data': l:startData })
    endif

    if has_key(a:ctx['opt'], 'stdin')
        let l:ctxCreate['stdinDispose'] = lsp#callbag#pipe(
            \ a:ctx['opt']['stdin'],
            \ lsp#callbag#subscribe({
            \   'next': (has('nvim') ? function('s:spawnNeovimStdinNext', [l:ctxCreate]) : function('s:spawnVimStdinNext', [l:ctxCreate])),
            \   'error': (has('nvim') ? function('s:spawnNeovimStdinError', [l:ctxCreate]) : function('s:spawnVimStdinError', [l:ctxCreate])),
            \   'complete': (has('nvim') ? function('s:spawnNeovimStdinComplete', [l:ctxCreate]) : function('s:spawnVimStdinComplete', [l:ctxCreate])),
            \ }),
            \ )
    endif

    if get(a:ctx['opt'], 'ready', 0)
        let l:readyData = { 'id': l:ctxCreate['jobid'], 'state': l:ctxCreate['state'] }
        if has_key(l:ctxCreate, 'pid') | let l:readyData['pid'] = l:ctxCreate['pid'] | endif
        call a:next({ 'event': 'ready', 'data': l:readyData })
    endif

    return function('s:spawnDispose', [l:ctxCreate])
endfunction

function! s:spawnJobStop(ctxCreate) abort
    if has('nvim')
        try
            call jobstop(a:ctxCreate['jobid'])
        catch /^Vim\%((\a\+)\)\=:E900/
            " NOTE:
            " Vim does not raise exception even the job has already closed so fail
            " silently for 'E900: Invalid job id' exception
        endtry
    else
        call job_stop(a:ctxCreate['job'])
    endif
endfunction

function! s:spawnDispose(ctxCreate) abort
    let a:ctxCreate['dispose'] = 1
    call s:spawnJobStop(a:ctxCreate)
endfunction

function! s:spawnNeovimStdinNext(ctxCreate, x) abort
    call jobsend(a:ctxCreate['jobid'], a:x)
endfunction

function! s:spawnVimStdinNext(ctxCreate, x) abort
    " Ref: https://groups.google.com/d/topic/vim_dev/UNNulkqb60k/discussion
    let a:ctxCreate['stdinBuffer'] .= a:x
    call s:spawnVimStdinNextFlushBuffer(a:ctxCreate)
endfunction

function! s:spawnVimStdinNextFlushBuffer(ctxCreate) abort
    " https://github.com/vim/vim/issues/2548
    " https://github.com/natebosch/vim-lsc/issues/67#issuecomment-357469091
    sleep 1m
    if len(a:ctxCreate['stdinBuffer']) <= 4096
        call ch_sendraw(a:ctxCreate['jobchannel'], a:ctxCreate['stdinBuffer'])
        let a:ctxCreate['stdinBuffer'] = ''
    else
        let l:to_send = a:ctxCreate['stdinBuffer'][:4095]
        let a:ctxCreate['stdinBuffer'] = a:ctxCreate['stdinBuffer'][4096:]
        call ch_sendraw(a:ctxCreate['jobchannel'], l:to_send)
        call timer_start(1, function('s:spawnVimStdinNextFlushBuffer', [a:ctxCreate]))
    endif
endfunction

function! s:spawnNeovimStdinError(ctxCreate, x) abort
    let a:ctxCreate['stdinError'] = a:x
    if get(a:ctxCreate['ctx']['opt'], 'failOnStdinError', 1) | call s:spawnJobStop(a:ctxCreate) | endif
endfunction

function! s:spawnVimStdinError(ctxCreate, x) abort
    let a:ctxCreate['stdinError'] = a:x
    if get(a:ctxCreate['ctx']['opt'], 'failOnStdinError', 1) | call s:spawnJobStop(a:ctxCreate) | endif
endfunction

function! s:spawnNeovimStdinComplete(ctxCreate) abort
    call chanclose(a:ctxCreate['jobid'], 'stdin')
endfunction

function! s:spawnVimStdinComplete(ctxCreate) abort
   " There is no easy way to know when ch_sendraw() finishes writing data
   " on a non-blocking channels -- has('patch-8.1.889') -- and because of
   " this, we cannot safely call ch_close_in().
    while len(a:ctxCreate['stdinBuffer']) != 0
        sleep 1m
    endwhile
    call ch_close_in(a:ctxCreate['jobchannel'])
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

function! s:spawnNeovimOnStdout(ctxCreate, id, d, event) abort
    call a:ctxCreate['next']({ 'event': 'stdout', 'data': a:ctxCreate['normalize'](a:d), 'state': a:ctxCreate['state'] })
endfunction

function! s:spawnNeovimOnStderr(ctxCreate, id, d, event) abort
    call a:ctxCreate['next']({ 'event': 'stderr', 'data': a:ctxCreate['normalize'](a:d), 'state': a:ctxCreate['state'] })
endfunction

function! s:spawnNeovimOnExit(ctxCreate, id, d, event) abort
    let a:ctxCreate['exit'] = 1
    let a:ctxCreate['close'] = 1
    let a:ctxCreate['exitcode'] = a:d
    call s:spawnNotifyExit(a:ctxCreate)
endfunction

function! s:spawnVimOutCb(ctxCreate, id, d, ...) abort
    echom 'out'
    call a:ctxCreate['next']({ 'event': 'stdout', 'data': a:ctxCreate['normalize'](a:d), 'state': a:ctxCreate['state'] })
endfunction

function! s:spawnVimErrCb(ctxCreate, id, d, ...) abort
    call a:ctxCreate['next']({ 'event': 'stderr', 'data': a:ctxCreate['normalize'](a:d), 'state': a:ctxCreate['state'] })
endfunction

function! s:spawnVimExitCb(ctxCreate, id, d) abort
    let a:ctxCreate['exit'] = 1
    let a:ctxCreate['exitcode'] = a:d
    " for more info refer to :h job-start
    " job may exit before we read the output and output may be lost.
    " in unix this happens because closing the write end of a pipe
    " causes the read end to get EOF.
    " close and exit has race condition, so wait for both to complete
    if a:ctxCreate['close'] && a:ctxCreate['exit']
        call s:spawnNotifyExit(a:ctxCreate)
    endif
endfunction

function! s:spawnVimCloseCb(ctxCreate, id) abort
    let a:ctxCreate['close'] = 1
    if a:ctxCreate['close'] && a:ctxCreate['exit']
        call s:spawnNotifyExit(a:ctxCreate)
    endif
endfunction

function! s:spawnNotifyExit(ctxCreate) abort
    if a:ctxCreate['dispose'] | return | end
    if has_key(a:ctxCreate, 'stdinDispose') | call a:ctxCreate['stdinDispose']() | endif
    if get(a:ctxCreate['ctx']['opt'], 'failOnStdinError', 1) && has_key(a:ctxCreate, 'stdinError')
        call a:ctxCreate['error'](a:ctxCreate['stdinError'])
        return
    endif
    if get(a:ctxCreate['ctx']['opt'], 'exit', 0)
        call a:ctxCreate['next']({ 'event': 'exit', 'data': a:ctxCreate['exitcode'], 'state': a:ctxCreate['state'] })
    endif
    if get(a:ctxCreate['ctx']['opt'], 'failOnNonZeroExitCode', 1) && a:ctxCreate['exitcode'] != 0
        call a:ctxCreate['error']('Spawn for job ' . a:ctxCreate['jobid'] .' failed with exit code ' . a:ctxCreate['exitcode'] . '. ')
    else
        call a:ctxCreate['complete']()
    endif
endfunction
" }}}

" vim: set sw=4 ts=4 sts=4 et tw=78 foldmarker={{{,}}} foldmethod=marker foldlevel=1 spell:
