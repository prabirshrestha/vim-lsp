-- 5cd1a589b7659e7d54dc37eccbccd80726f19374
local t_string = 'string'
local t_function = 'function'
local t_table = 'table'

local uv
local noop = function () end
local unpack = table.unpack or unpack

local clone = function (o)
    return { unpack(o) }
end

local indexOf = function (t, obj)
    if type(t) ~= 'table' then error('table expected. got ' .. type(t), 2) end
    for i, v in ipairs(t) do
        if obj == v then
            return i
        end
    end
    return -1
end

local clear = function (t)
    for i, v in ipairs(t) do
        t[i] = nil
    end
end


local M = {}

-- vim sepecific bootstrap
local callbag_id = 0
local vimcmd
local vimeval

local addListener
local removeListener

local initvim = function ()
    if vim.api ~= nil then
        vimcmd = vim.api.nvim_command
        vimeval = vim.api.nvim_eval
        uv = vim.loop
    else
        vimcmd = vim.command
        vimeval = vim.eval
    end

    callbag_id = vimeval('get(g:, "lua_callbag_id", 0)') + 1
    vimcmd('let g:lua_callbag_id = ' .. callbag_id)

    local globalAutoCmdHandlerName = 'lua_callbag_autocmd_handler_' .. callbag_id
    local autoCmdHandlers = {}
    _G[globalAutoCmdHandlerName] = function (name)
        autoCmdHandlers[name]()
    end

    addListener = function (name, events, cb)
        autoCmdHandlers[name] = cb
        vimcmd('augroup ' .. name)
        vimcmd('autocmd!')
        for _, v in ipairs(events) do
            local cmd = 'lua ' .. globalAutoCmdHandlerName .. '("' .. name ..'")'
            vimcmd('au ' .. v .. ' ' .. cmd)
        end
        vimcmd('augroup end')
    end

    removeListener = function (name)
        vimcmd('augroup ' .. name)
        vimcmd('autocmd!')
        vimcmd('augroup end')
        autoCmdHandlers[name] = nil
    end
end

if vim and vim.fn then initvim() end
-- end vim specific bootstrap

function M.pipe(...)
    local arg = {...}
    local res = arg[1]
    for i = 2,#arg do
        res = arg[i](res)
    end
    return res
end

function M.create(producer)
    return function (start, sink)
        if start ~= 0 then return end
        if type(producer) ~= t_function then
            sink(0, noop)
            sink(2)
            return
        end
        local ended = false
        local clean
        sink(0, function (t)
            if not ended then
                ended = t == 2
                if ended and type(clean) == t_function then
                    clean()
                end
            end
        end)
        if ended then return end
        clean = producer(
            function (v)
                if not ended then sink(1, v) end
            end,
            function (e)
                if not ended and e ~= nil then
                    ended = true
                    sink(2, e)
                end
            end,
            function ()
                if not ended then
                    ended = true
                    sink(2)
                end
            end)
    end
end

function M.empty()
    return function (start, sink)
        if start ~= 0 then return end
        local disposed = false
        sink(0, function (t)
            if t ~= 2 then return end
            disposed = true
        end)
        if disposed then return end
        sink(2)
    end
end

function M.never()
    return function (start, sink)
        if start ~= 0 then return end
        sink(0, noop)
    end
end

function M.lazy(f)
    return function (start, sink)
        if start == 0 then
            local unsubed = false
            sink(0, function (t)
                if t == 2 then unsubed = true end
            end)
            sink(1, f())
            if not unsubed then sink(2) end
        end
    end
end

function M.fromIPairs(values)
    return function (start, sink)
        if start ~= 0 then return end
        local disposed = false
        sink(0, function (type)
            if type ~= 2 then return end
            disposed = true
        end)

        for _, value in ipairs(values) do
            if disposed then return end
            sink(1, value)
        end

        if disposed then return end

        sink(2)
    end
end

function M.makeSubject()
    local sinks = {}
    local done = false
    return function (typ, data)
        if done then return end
        if typ == 0 then
            local sink = data
            table.insert(sinks, data)
            sink(0, function (t)
                if t == 2 then
                    local i = indexOf(sinks, sink)
                    if i > -1 then
                        table.remove(sinks, i)
                    end
                end
            end)
        else
            local zinkz = clone(sinks)

            for i = 1, #zinkz do
                local sink = zinkz[i]
                if indexOf(sinks, sink) > -1 then
                    sink(typ, data)
                end
            end

            if typ == 2 then
                done = true
                clear(sinks)
            end
        end
    end
end

local fromEventId = 0
function M.fromEvent(events, ...)
    local arg = {...}

    return function (start, sink)
        if start ~= 0 then return end
        local disposed = false
        local eventName
        local handler = function ()
            sink(1, nil)
        end
        sink(0, function (t)
            if t ~= 2 then return end
            disposed = true
            if eventName ~= nil then
                removeListener(eventName)
            end
        end)

        if disposed then return end

        if type(events) == t_string then
            events = { events }
        end

        local listenerEvents = {}
        for _, v in ipairs(events) do
            if type(v) == t_string then
                table.insert(listenerEvents, v .. ' * ')
            else
                table.insert(listenerEvents, table.join(v, ','))
            end
        end

        if #arg > 0 then
            eventName = arg[1]
        else
            fromEventId = fromEventId + 1
            eventName = '__lua_callbag_' .. callbag_id .. '_fromEvent_' .. fromEventId .. '__'
        end

        addListener(eventName, listenerEvents, handler)
    end
end

function M.forEach(operation)
    return function (source)
        local talkback
        source(0, function (t, d)
            if t == 0 then talkback = d end
            if t == 1 then operation(d) end
            if (t == 1 or t == 0) then talkback(1) end
        end)
    end
end

function M.subscribe(listener)
    if not listener then listener = {} end
    return function (source)
        if type(listener) == t_function then listener = { next = listener } end

        local nextcb = listener['next']
        local errorcb = listener['error']
        local completecb = listener['complete']

        local talkback

        source(0, function (t, d)
            if t == 0 then talkback = d end
            if t == 1 and nextcb then nextcb(d) end
            if t == 1 or t == 0 then talkback(1) end -- pull
            if t == 2 and not d and completecb then completecb() end
            if t == 2 and d and errorcb then errorcb(d) end
        end)

        local dispose = function ()
            if talkback then talkback(2) end
        end

        return dispose
    end
end

function M.merge(...)
    local sources = {...}
    return function (start, sink)
        if start ~= 0 then return end
        local n = #sources
        local sourceTalkbacks = {}
        local startCount = 0
        local endCount = 0
        local ended = false
        local talkback = function (t, d)
            if t == 2 then ended = true end
            for i = 1, n do
                if sourceTalkbacks[i] then
                    sourceTalkbacks[i](t, d)
                end
            end
        end
        for i = 1, n do
            if ended then return end
            sources[i](0, function (t, d)
                if t == 0 then
                    sourceTalkbacks[i] = d
                    startCount = startCount + 1
                    if startCount == 1 then
                        sink(0, talkback)
                    end
                elseif t == 2 and d then
                    ended = true
                    for j = 1, n do
                        if j ~= i then
                            if sourceTalkbacks[j] then
                                sourceTalkbacks[j](2)
                            end
                        end
                    end
                    sink(2, d)
                elseif t == 2 then
                    sourceTalkbacks[i] = nil
                    endCount = endCount + 1
                    if endCount == n then
                        sink(2)
                    end
                else
                    sink(t, d)
                end
            end)
        end
    end
end

function M.filter(condition)
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            local talkback
            source(0, function (t, d)
                if t == 0 then
                    talkback = d
                    sink(t, d)
                elseif t == 1 then
                    if condition(d) then
                        sink(t, d)
                    else
                        talkback(1)
                    end
                else
                    sink(t, d)
                end
            end)
        end
    end
end

function M.map(f)
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            source(0, function (t, d)
                if t == 1 then
                    sink(t, f(d))
                else
                    sink(t, d)
                end
            end)
        end
    end
end

function M.tap(...)
    local args = {...}
    local argc = #args
    local nextcb
    local errorcb
    local completecb
    if argc > 0 and type(args[1]) == t_table then
        -- args[1] = { next, error, complete }
        nextcb = args[1]['next']
        errorcb = args[1]['error']
        completecb = args[1]['complete']
    else
        -- args[1] = next, args[2] = error, args[3] = complete
        if argc > 0 then nextcb = args[1] end
        if argc > 1 then errorcb = args[2] end
        if argc > 2 then completecb = args[3] end
    end
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            source(0, function (t, d)
                if t == 1 and d and nextcb then
                    nextcb(d)
                elseif t == 2 then
                    if d then
                        if errorcb then errorcb(d) end
                    else
                        if completecb then completecb() end
                    end
                end
                sink(t, d)
            end)
        end
    end
end

local distinctUntilChangedDefaultComparator = function (previous, current)
    return previous == current
end

function M.distinctUntilChanged(compare)
    if not compare then compare = distinctUntilChangedDefaultComparator end
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            local inited = false
            local previous
            local talkback
            source(0, function (t, d)
                if t == 0 then talkback= d end
                if t~= 1 then
                    sink(t, d)
                    return
                end
                if inited and compare(previous, d) then
                    talkback(1)
                    return
                end

                inited = 1
                previous = d
                sink(1, d)
            end)
        end
    end
end

function M.debounceTime(wait)
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            local timeout
            source(0, function (t, d)
                if t == 1 or (t == 2 and d == nil) then
                    if not timeout and t == 2 then
                        sink(t, d)
                        return
                    end

                    if timeout then
                        vim.fn.timer_stop(timeout)
                    end

                    timeout = vim.fn.timer_start(wait, function ()
                        sink(t, d)
                        timeout = nil
                    end)
                else
                    sink(t, d)
                end
            end)
        end
    end
end

local takeUntilUnique = {}
function M.takeUntil(notifier)
    return function (source)
        return function (start, sink)
            if start ~= 0 then return end
            local sourceTalkback
            local notifierTalkback
            local inited = false
            local done = takeUntilUnique

            source(0, function (typ, data)
                if typ == 0 then
                    sourceTalkback = data

                    notifier(0, function (t, d)
                        if t == 0 then
                            notifierTalkback = d
                            notifierTalkback(1)
                            return
                        end
                        if t == 1 then
                            done = nil
                            notifierTalkback(2)
                            sourceTalkback(2)
                            if inited then sink(2) end
                            return
                        end
                        if t == 2 then
                            notifierTalkback = nil
                            done = d
                            if d ~= nil then
                                sourceTalkback(2)
                                if inited then sink(t, d) end
                            end
                        end
                    end)

                    inited = true

                    sink(0, function (t, d)
                        if done ~= takeUntilUnique then return end
                        if t == 2 and notifierTalkback then notifierTalkback(2) end
                        sourceTalkback(t, d)
                    end)

                    if done ~= takeUntilUnique then sink(2, done) end
                    return
                end

                if typ == 2 then notifierTalkback(2) end
                if done == takeUntilUnique then sink(typ, data) end
            end)
        end
    end
end

function M.switchMap(makeSource, combineResults)
    return function (inputSource)
        return function (start, outputSink)
            if start ~= 0 then return end
            if not combineResults then
                combineResults = function (x, y) return y end
            end
            local currSourceTalkback = nil
            local sourceEnded = false

            inputSource(0, function (t, d)
                if t == 0 then outputSink(t, d) end
                if t == 1 then
                    if currSourceTalkback then
                        currSourceTalkback(2)
                        currSourceTalkback = nil
                    end

                    local currSource = makeSource(d)

                    currSource(0, function (currT, currD)
                        if currT == 0 then currSourceTalkback = currD end
                        if currT == 1 then outputSink(t, combineResults(d, currD)) end
                        if currT == 0 or currT == 1 then
                            if currSourceTalkback then currSourceTalkback(1) end
                        end
                        if currT == 2 then
                            currSourceTalkback = nil
                            if sourceEnded then outputSink(currT, currD) end
                        end
                    end)
                end
                if t == 2 then
                    sourceEnded = true
                    if not currSourceTalkback then
                        outputSink(t, d)
                    end
                end
            end)
        end
    end
end

local function spawn_uv(cmd, opt)
    return M.create(function (next, err, complete)
        if not opt then opt = {} end
        local command = cmd[1]
        if not (vim.fn.executable(command) == 1) then
            err('Command ' .. command .. ' not found.')
            return
        end
        local spawn_options = {}
        local handle
        local pid
        local stdin = uv.new_pipe(false)
        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        local disposeStdin
        local stdinErr
        local failOnNonZeroExitCode = opt['failOnNonZeroExitCode']
        if failOnNonZeroExitCode == nil then failOnNonZeroExitCode = true end
        local failOnStdinError = opt['failOnStdinErr']
        if failOnStdinError == nil then failOnStdinError = true end

        local function close_safely(handle)
            if handle and not handle:is_closing() then
                handle:close()
            end
        end

        local function on_stdout(err, data)
            if err then
                -- TODO: handle error
                return
            end
            if opt['stdout'] and data then -- nil data means end of stdout
                next({ event = 'stdout', data = data, state = opt['state'] })
            end
        end

        local function on_stderr(err, data)
            if err then
                -- TODO: handle error
                return
            end
            if opt['stderr'] and data then -- nil data means end of stderr
                next({ event = 'stderr', data = data, state = opt['state'] })
            end
        end

        local function cleanup()
            if disposeStdin then
                disposeStdin()
                disposeStdin = nil
            end
            if stdout then stdout:read_stop() end
            if stderr then stderr:read_stop() end
            close_safely(stdin)
            close_safely(stdout)
            close_safely(stderr)
            close_safely(handle)
        end

        local function on_exit(exitcode, signal)
            cleanup()
            if opt['exit'] then
                next({ event = 'exit', data = { exitcode = exitcode }, state = opt['state'] })
            end
            if failOnStdinError and stdinErr then
                err(stdinErr)
                return
            end
            if failOnNonZeroExitCode and exitcode ~= 0 then
                err('Spawn for job failed with exit code ' .. exitcode .. '.')
            else
                complete()
            end
        end

        spawn_options['args'] = {unpack(cmd, 2, #cmd)}
        spawn_options['stdio'] = { stdin, stdout, stderr }
        if opt['cwd'] then spawn_options['cwd'] = opt['cwd'] end
        if opt['env'] then spawn_options['env'] = opt['env'] end

        handle, pid = uv.spawn(command, spawn_options, on_exit)

        if opt['start'] then
            next({ event = 'start', data = { state = opt['state'] } })
        end

        if opt['stdin'] then
            disposeStdin = M.pipe(
                opt['stdin'],
                M.subscribe({
                    next = function (d)
                        stdin:write(d)
                    end,
                    error = function (e)
                        stdinErr = e
                        close_safely(stdin)
                        if failOnStdinError then close_safely(handle) end
                    end,
                    complete = function ()
                        close_safely(stdin)
                    end
                })
            )
        end

        if opt['ready'] then
            next({ event = 'ready', data = { state = opt['state'], pid = pid } })
        end

        if opt['stdout'] then uv.read_start(stdout, on_stdout) end
        if opt['stderr'] then uv.read_start(stderr, on_stderr) end

        return function ()
            cleanup()
        end
    end)
end

-- spawn {{{
-- let stdin = C.makeSubject()
-- C.pipe(
--  C.spawn({'bash', '-c', 'read i; echo $i'}, {
--   stdin = stdin,
--   stdout = false,
--   stderr = false,
--   exit = false,
--   start = false -- when job starts before subscribing to stdin
--   ready = false -- when job starts and after subscribing to stdin
--   pid = false,
--   failOnNonZeroExitCode = true,
--   failOnStdinError = true,
--   env = {}
--   cwd = ''
--  ),
--  C.subscribe({})
-- )
-- stdin(1, 'hello')
-- stdin(1, 'world')
-- stdin(2) -- required to close stdin
function M.spawn(cmd, opt)
    if not opt then opt = {} end
    local command = cmd[1]
    if uv then
        return spawn_uv(cmd, opt)
    else
        return err('spawn not implemented')
    end
end

return M
