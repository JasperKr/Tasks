---@type love.Channel, love.Channel
local receive, send, sendHasQuit, myPath = ...

require("love.filesystem")

local messages = require(myPath .. ".message")
local tasks = require(myPath .. ".task")

local function taskError(error)
    send:push(messages.newCallback("error", error, "error"))
end

Rhodium = {
    internal = {},
    math = {},
}

require("love.image")
require("love.timer")

local pathToFunc = {}

local function runTask(message)
    local task = tasks.unpack(message.data)

    local func, success, ret

    if task.thread.isPath then
        if not pathToFunc[task.thread.path] then
            func = love.filesystem.load(task.thread.path)
            pathToFunc[task.thread.path] = func
        else
            func = pathToFunc[task.thread.path]
        end
    else
        func, ret = loadstring(task.thread.code)

        ---@cast func fun(any, ...):any
    end

    success, ret = xpcall(func, debug.traceback, unpack(task.data))

    if not success then
        taskError(tostring(task.thread.path) .. ": " .. ret)
    else
        send:push(messages.new(task.id, "task done", "message", ret))
    end
end

while true do
    local data = receive:demand()

    if data == "quit" then
        sendHasQuit:push(true)
        break
    end

    local message = messages.unpack(data)

    runTask(message)
end
