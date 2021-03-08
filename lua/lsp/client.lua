local C = require 'lsp/callbag'
local inspect = require 'lsp/inspect'

local M = {}

local send_type_request = 1
local send_type_notification = 2
local send_type_response = 3

local vimeval
local vimcmd
if vim.api ~= nil then
    vimcmd = vim.api.nvim_command
    vimeval = vim.api.nvim_eval
    uv = vim.loop
else
    vimcmd = vim.command
    vimeval = vim.eval
end

local function json_encode(obj)
    return vim.fn.json_encode(obj)
end

local function json_decode(str)
    return vim.fn.json_decode(str)
end

local function log(...)
    local args = {...}
    vim.fn.call('lsp#log', args)
end

local client_index = 0
local function new_client_id()
    client_index = client_index + 1
    return client_index
end

-- {
--    dispose = function() end,
--    buffer = ''
--    client_id,
--    request_sequence = 0,
--    pid = 123
--    stdin = C.makeSubject()
--    requests = {}
--    on_notifications = {}
-- }
local clients = {}

local function on_ready(x)
    x.data.state.pid = x.data.pid
end

local function get_content_length(header_string)
    local headers = {}
    for k, v in header_string:gmatch("([%a%d%-]+): ([%g ]+)\r\n") do
        if k == nil then error("Unparseable Header") end
        headers[k:lower()] = v
    end
    return tonumber(headers['content-length'])
end

local function on_stdout(x)
    local state = x.state
    state.buffer = state.buffer .. x.data
    while true do
        if state.content_length < 0 then
            local header_end_index = state.buffer:find('\r\n\r\n', 1, true)
            if header_end_index < 0 then
                return
            end
            local headers = state.buffer:sub(1, header_end_index - 1)
            state.content_length = get_content_length(headers .. '\r\n')
            if state.content_length < 0 then
                -- invalid content length
                M.stop(state.client_id)
                return
            end
            state.buffer = state.buffer:sub(header_end_index + 4)
        end

        if #state.buffer < state.content_length then
            -- incomplete message, wait for next buffer to arrive
            return
        end

        -- we have full message
        local response_str = state.buffer:sub(1, state.content_length)
        state.content_length = -1

        -- TODO: try..catch json_decode
        local response = json_decode(response_str)

        state.buffer = state.buffer:sub(#response_str + 1)

        if response then
            -- call appropriate callbacks
            local on_notification_data = { response = response }
            local request
            if response.method and response.id then
                -- it is a request from a server
                request = response
                if state.options.on_request then
                    state.options.on_request(state.client_id, request)
                end
            elseif response.id then
                -- it is a request->response
                if state.requests[response.id] then
                    on_notification_data['request'] = state.requests[response.id]
                end
                if state.options.on_notification then
                    -- call client's on_notification first
                    -- TODO: try..catch
                    log('call')
                    state.options.on_notification(state.client_id, on_notification_data, 'on_notification')
                end
                if state.on_notifications[response.id] then
                    log('call2')
                    -- TODO: try..catch
                    state.on_notifications[response.id](state.client_id, on_notification_data, 'on_notification')
                    state.on_notifications[response.id] = nil
                end
                    log('call3')
                if state.requests[response.id] then
                    state.requests[response.id] = nil
                end
            else
                -- it is a notification
                if state.options.on_notification then
                    state.options.on_notification(state.client_id, on_notification_data, 'on_notification')
                end
            end
        end

        if state.buffer == "" then
            -- buffer is empty, wait for next message to arrive
            return
        end
    end
end
if vim.api then on_stdout = vim.schedule_wrap(on_stdout) end

local function on_stderr(x)
    -- log('stderr')
end

local function on_exit(x)
    log('exit')
end

local spawn_on_next = {
    ready = on_ready,
    stdout = on_stdout,
    stderr = on_stderr,
    exit = on_exit,
}

function M.start(options)
    for k,v in pairs(options) do
        log(k)
    end
    local state = {
        buffer = '',
        client_id = new_client_id(),
        content_length = -1,
        request_sequence = 0,
        requests = {},
        on_notifications = {},
        options = options,
        stdin = C.makeSubject()
    }

    clients[state.client_id] = state

    if options['tcp'] then
        -- TODO: TCP not supported
        return -1
    end

    local dispose = C.pipe(
        C.spawn(options['cmd'], { ready = true, stdin = state['stdin'], stderr = true, stdout = true, state = state }),
        C.subscribe({
            next = function(x) spawn_on_next[x['event']](x) end,
            error = function (e) print(inspect(e)) end,
            complete = function () end
        })
    )
    state['dispose'] = dispose

    return state.client_id
end

function M.stop(id)
    local state = clients[id]
    if state then
        if state.dispose then
            state.dispose()
            state.dispose = nil
        end
        clients[id] = nil
    end
end

function M.send(id, options, typ)
    local state = clients[id]
    if not state then return -1 end

    local request = { jsonrpc = '2.0' }

    if typ == send_type_request then
        state.request_sequence = state.request_sequence + 1
        request.id = state.request_sequence
        state.requests[request.id] = request
        if options.on_notification then
            state.on_notifications[option.request.id] = options['on_notification']
        end
    end

    if options.id then request.id = options.id end
    if options.method then request.method = options.method end
    if options.params then request.params = options.params end
    if options.result then request.result = options.result end
    if options.error then request.error = options.error end

    local json = json_encode(request)
    local payload = 'Content-Length: ' .. #json .. '\r\n\r\n' .. json
    state.stdin(1, payload)

    if typ == send_type_request then
        local id = request.id
        local sync = options.sync or 0
        if sync ~= 0 then
            -- TODO: implement wait
        end
        return id
    else
        return 0
    end
end

function M.send_notification(id, options)
end

function M.send_response(id, options)
end

function M.get_last_request_id(id)
    return clients[id].request_sequence
end

function M.is_error(obj_or_response)
    return false
end

function M.error_message(obj_or_response)
end

function M.is_server_instantiated_notification(notification)
end

return M
