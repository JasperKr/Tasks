local path = ...

local messages = require(path .. ".message")
local tasks = require(path .. ".task")
local newObjectIndexedTable = require(path .. ".tables").newObjectIndexedTable

--[[
    tasks are a way to run code in the background without blocking the main thread
    tasks run if there is no other code running, if there is code running,
    the task will be queued and run after the code is done running so there aren't any lag spikes
]]

local task = {}

local verificationEnabled = false

function task.enableVerification(enable)
    verificationEnabled = enable
end

local threading = {}
threading.threads = {}
threading.send = love.thread.newChannel()
threading.receiveHasQuit = love.thread.newChannel()
threading.receive = love.thread.newChannel()

task.threading = threading

local processorCount = love.system.getProcessorCount()

for i = 1, processorCount do
    threading.threads[i] = love.thread.newThread(path .. "/tasksThread.lua")
    threading.threads[i]:start(threading.send, threading.receive, threading.receiveHasQuit, path)
end

local idCounters = {}

local function newID(i)
    i = i or "Global"
    idCounters[i] = (idCounters[i] or 0) + 1
    return idCounters[i] - 1
end

---@type taskGroup|nil
local taskGroup

---@type taskGroup
local defaultTaskGroup

---@type {[1]:{group: taskGroup, command:table}}
local commandBuffer = {}

local taskIDToGroup = {}

local tasksRunning = {}
local tasksQueued = {}
local filesChecked = {}

local wrappedFunctions = newObjectIndexedTable()

local function verifyData(path, data)
    if type(data) == "table" then
        for key, value in pairs(data) do
            verifyData(path .. "." .. key, value)
        end
    elseif type(data) == "function" then
        error("Function in data: " .. path)
    elseif type(data) == "cdata" then
        error("Cdata in data: " .. path)
    elseif type(data) == "userdata" then
        if not data:typeOf("Data") then
            error("Userdata in data: " .. path)
        end
    end
end

--- queues a command to be ran by the threads
---@param command table the command to run
---@param group taskGroup the group the command is in
local function sendCommand(command, group)
    if verificationEnabled then
        verifyData("command", command.data.data)
    end

    task.threading.send:push(command)

    group.amountRunning = group.amountRunning + 1
    group.amountQueued = group.amountQueued - 1

    taskIDToGroup[command.data.id] = group

    tasksRunning[command.data.id] = tasksQueued[command.data.id]
    tasksQueued[command.data.id] = nil
end

-- a task group describes a group of tasks that are run together
-- if it has any dependencies, the group will wait for the dependencies to finish before running

--- add a task to the queue
---@param thread taskThread the path to the file to run
---@param args table|nil
local function newTaskInternal(thread, args, callback)
    if thread.path then
        local path = thread.path

        assert(path)

        if not filesChecked[path] then
            filesChecked[path] = true
            if love.getVersion() == 12 then
                ---@diagnostic disable-next-line: undefined-field
                assert(love.filesystem.exists(path), "File does not exist: " .. path)
            else
                assert(love.filesystem.getInfo(path, "file"), "File does not exist: " .. path)
            end
        end
    end

    local self = tasks.new("task", args, thread)

    tasksQueued[self.id] = {
        task = self,
        callback = callback,
    }

    local group = taskGroup or defaultTaskGroup

    group.amountQueued = group.amountQueued + 1
    group.totalQueued = group.totalQueued + 1

    if group:canRun() then
        sendCommand(messages.new(self.id, "task", "task start", self:pack()), group)
    else
        table.insert(commandBuffer, 1,
            {
                group = group,
                command = messages.new(self.id, "task", "task start", self:pack()),
            }
        )
    end

    return self
end

--- add a task to the queue and execute it sequentially
--- this is useful for tasks that depend on each other
---@param thread taskThread the path to the file to run
---@param args table|nil
---@param callback function|nil
function task.newSyncedTask(thread, args, callback)
    local group = taskGroup
    local newGroup

    if group ~= defaultTaskGroup then
        newGroup = task.newTaskGroup(group)
    else
        newGroup = task.newTaskGroup()
    end

    task.setTaskGroup(newGroup)

    local newTask = newTaskInternal(thread, args, callback)

    return newTask, newGroup
end

--- add a task to the queue and execute it (as soon as the current group allows it)
---@param thread taskThread the path to the file to run
---@param args table|nil
---@param callback function|nil
function task.newTask(thread, args, callback)
    return newTaskInternal(thread, args, callback)
end

--- add a task to the queue without waiting for other tasks to finish
function task.newAsyncTask(thread, args, callback)
    task.setTaskGroup()
    return newTaskInternal(thread, args, callback)
end

--- get the status of a task
---@return "running"|"queued"|"done" status
function task.taskStatus(task)
    if tasksRunning[task.id] then
        return "running"
    elseif tasksQueued[task.id] then
        return "queued"
    else
        return "done"
    end
end

--- get the status of a group
---@param group taskGroup
---@return "running" | "done" | "queued"
---@return integer amount amount of threads left
function task.groupStatus(group)
    if group:isRunning() then
        return "running", group.amountRunning + group.amountQueued
    elseif group:isQueued() then
        return "queued", group.amountQueued
    elseif group:isDone() then
        return "done", group.amountDone
    else
        error("Invalid group status")
    end
end

---@class taskGroup
---@field type "Task group"
---@field id integer
---@field dependencies {[1]:taskGroup|nil}
---@field amountRunning integer
---@field amountQueued integer
---@field amountDone integer
---@field totalQueued integer
local taskGroupFunctions = {}
local taskGroupMetatable = {}

taskGroupMetatable.__index = taskGroupFunctions

--- create a new task group
---@param dependencies taskGroup|nil|{[1]:taskGroup}
---@return taskGroup
function task.newTaskGroup(dependencies)
    if dependencies and dependencies.type == "Task group" then
        dependencies = { dependencies }
    end

    if dependencies == nil then
        dependencies = {}
    end

    ---@cast dependencies {[1]:taskGroup}

    local self = {
        type          = "Task group",
        id            = newID("Task group"),
        dependencies  = dependencies,

        amountRunning = 0, -- amount of tasks currently running
        amountQueued  = 0, -- amount of tasks queued
        amountDone    = 0, -- amount of tasks done

        totalQueued   = 0, -- total amount of tasks queued (so we can check if the group is done)
    }

    setmetatable(self, taskGroupMetatable)

    return self
end

--- check if the task group is running, the group can still be queued if you dispatch before adding all tasks
---@return boolean
function taskGroupFunctions:isRunning()
    return self.amountRunning > 0
end

--- check if the task group is done
function taskGroupFunctions:isDone()
    return self.amountDone == self.totalQueued
end

--- check if the task group is queued
function taskGroupFunctions:isQueued()
    return self.amountQueued > 0
end

--- check if a task group can run
function taskGroupFunctions:canRun()
    local canRun = true
    for i, group in ipairs(self.dependencies) do
        canRun = canRun and group:isDone()
    end

    return canRun
end

defaultTaskGroup = task.newTaskGroup()

--- set the task group to run tasks in
---@param group taskGroup|nil
function task.setTaskGroup(group)
    taskGroup = group
end

--- create and set a new task group to run tasks in
---@param dependencies taskGroup|nil|{[1]:taskGroup}
function task.setNewTaskGroup(dependencies)
    taskGroup = task.newTaskGroup(dependencies)

    return taskGroup
end

function task.runTasks()
    local data = task.threading.receive:pop()

    while data do -- receive task thread data
        local message = messages.unpack(data)

        if message.type == "message" then
            if message.messageType == "task done" then
                local taskData = tasksRunning[message.id]

                tasksRunning[message.id] = nil

                if taskData.callback then
                    taskData.callback(message.data)
                end

                local group = taskIDToGroup[message.id]

                assert(group, "Group not found")

                group.amountRunning = group.amountRunning - 1
                group.amountDone = group.amountDone + 1
            else
                print("Unknown message type: " .. message.messageType)
            end
        elseif message.type == "callback" then
            if message.callbackType == "error" then
                if message.name == "error" then
                    print("Task error: " .. message.data)
                end
            end
        end

        data = task.threading.receive:pop()
    end

    for i = #commandBuffer, 1, -1 do
        local commandData = commandBuffer[i]

        if commandData.group:canRun() then
            sendCommand(commandData.command, commandData.group)

            table.remove(commandBuffer, i)
        end
    end

    for i, wrappedFunction in ipairs(wrappedFunctions.items) do
        wrappedFunction:update()
    end
end

function task.Shutdown()
    -- clear the channels
    task.threading.receiveHasQuit:clear()
    task.threading.send:clear()

    -- send quit message to all threads
    for i = 1, processorCount do
        task.threading.send:push("quit")
    end

    -- wait for all threads to quit
    for i = 1, processorCount do
        task.threading.threads[i].thread:wait()
    end
end

function task.getTasksQueuedCount()
    return task.threading.send:getCount()
end

---@class taskThread
---@field path string?
---@field code string?
---@field isPath boolean

--- create a new task thread
---@param path string the path to the file to run or the code to run if isPath is false
---@param isPath boolean? if the path is a file path or code
---@return taskThread
function task.newTaskThread(path, isPath)
    if isPath == nil then
        isPath = false
    end

    local thread = {
        isPath = isPath,
    }

    if isPath then
        thread.path = path
    else
        thread.code = path
    end

    return thread
end

--- (only for coroutines), waits for the group or task to complete
---
--- gives any extra parameters to the coroutine.yield.
---@param data task | taskGroup
function task.await(data, ...)
    if data.type == "task" then
        ---@cast data task

        while task.taskStatus(data) ~= "done" do
            coroutine.yield(...)
        end
    elseif data.type == "Task group" then
        ---@cast data taskGroup

        while task.groupStatus(data) ~= "done" do
            coroutine.yield(...)
        end
    else
        error("Invalid parameter")
    end
end

--- (only for coroutines), waits for the function to return true
--- gives any extra parameters to that function
--- @param func function the function to run
--- @vararg any extra parameters to pass to the function
function task.barrier(func, ...)
    while not func(...) do
        coroutine.yield()
    end
end

function task.yield(condition)
    if condition ~= false then -- explicitly check for not false, nil should be allowed
        coroutine.yield()
    end
end

function task.demand(...)
    local running = true
    while running do
        running = false

        task.runTasks()

        for i = 1, select("#", ...) do
            local data = select(i, ...)
            if data.type == "task" then
                ---@cast data task

                while task.taskStatus(data) ~= "done" do
                    running = true
                end
            elseif data.type == "Task group" then
                ---@cast data taskGroup

                while task.groupStatus(data) ~= "done" do
                    running = true
                end
            else
                error("Invalid parameter")
            end
        end
    end
end

local wrappedFunctionsMetatable = {}

---@class wrappedAsyncFunction
---@field func function
---@field doneCallback function
---@field busyCallback function
---@field routine thread?
local wrappedFunctionsFunctions = {} -- O_o
wrappedFunctionsMetatable.__index = wrappedFunctionsFunctions

local function updateWrappedFunction(self, ...)
    if select(2, ...) == "cannot resume dead coroutine" then
        if self.doneCallback then
            self.doneCallback(select(2, ...))
            wrappedFunctions:removeAsObject(self)
        end
        return
    end

    if select(1, ...) == false and type(select(2, ...) == "string") then
        error(select(2, ...))
    end

    if coroutine.status(self.routine) == "dead" then
        if self.doneCallback then
            self.doneCallback(select(2, ...))
            wrappedFunctions:removeAsObject(self)
        end
        return
    end

    if not select(1, ...) then
        print("Error: " .. select(2, ...))
        wrappedFunctions:removeAsObject(self)
        return
    end

    if self.busyCallback then
        self.busyCallback(select(2, ...))
    end
end

--- wrap a function to run in the background
--- the function will check if it is done every frame and call the doneCallback when it is done
--- the busyCallback will be called every frame while the function is running with the returned parameters from coroutine.yield
---@param func function the function to run
---@param doneCallback function? the callback to call when the function is done
---@param busyCallback function? the callback to call every frame while the function is running
---@vararg any extra arguments to pass to the function
---@return wrappedAsyncFunction?
function task.wrapAsyncFunction(func, doneCallback, busyCallback, ...)
    local routine = coroutine.create(func)

    assert(type(func) == "function", "Function is not a function")
    assert(type(doneCallback) == "function" or doneCallback == nil, "Done callback is not a function")
    assert(type(busyCallback) == "function" or busyCallback == nil, "Busy callback is not a function")

    local self = {
        func = func,
        doneCallback = doneCallback,
        busyCallback = busyCallback,
        routine = routine,
    }

    setmetatable(self, wrappedFunctionsMetatable)
    wrappedFunctions:add(self)

    updateWrappedFunction(self, coroutine.resume(routine, ...))

    return self
end

function wrappedFunctionsFunctions:update(...)
    assert(self.routine, "Routine is nil")
    updateWrappedFunction(self, coroutine.resume(self.routine, ...))
end

function task.getThreadCount()
    return #task.threading.threads
end

local data = {}

for i, thread in ipairs(task.threading.threads) do
    data[i] = {
        active = false
    }
end

local info = setmetatable({}, {
    __index = data,
    __newindex = function()
        error("Attempt to modify a readonly table", 2)
    end,
})

function task.getInfo()
    for i, thread in ipairs(task.threading.threads) do
        data[i].active = thread.activeChannel:peek()
    end

    return info
end

function task.getActiveThreadCount()
    local count = 0

    for i, thread in ipairs(task.threading.threads) do
        if thread.activeChannel:peek() then
            count = count + 1
        end
    end

    return count
end

function task.getWrappedFunctionsCount()
    return #wrappedFunctions.items
end

function task.getQueuedTaskCount()
    return task.threading.send:getCount()
end

return task
