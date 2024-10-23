local taskMetatable = {}

---@class task
---@field name string
---@field data any
---@field type "task"
---@field thread taskThread
---@field id string
local taskFunctions = {}

taskMetatable.__index = taskFunctions

local idCounters = {}

local function newID(i)
    i = i or "Global"
    idCounters[i] = (idCounters[i] or 0) + 1
    return idCounters[i] - 1
end

--- create a new task
---@param name string
---@param data any
---@param thread taskThread
---@param id? string
---@return task
local function newTask(name, data, thread, id)
    local task = {
        name = name,
        data = data,
        type = "task",
        thread = thread,
        id = id or newID("Task"),
    }

    setmetatable(task, taskMetatable)

    return task
end

function taskFunctions:pack()
    -- does nothing for now
    return self
end

---@param data table
---@return task
local function unpackTask(data)
    assert(data.name)
    assert(data.data)
    assert(data.type == "task")
    assert(data.thread)
    assert(data.id)

    return newTask(data.name, data.data, data.thread, data.id)
end

return {
    new = newTask,
    unpack = unpackTask,
}
