local messageMetatable = {}

---@class Rhodium.taskMessage
---@field name string
---@field data any
---@field type "message"|"callback"|"quit"
---@field callbackType "error"|"timeout"
---@field id string
---@field messageType string
local messageFunctions = {}
messageMetatable.__index = messageFunctions

-- things i can think of right now, might be changed later

---@alias callbackType "error"|"timeout"

local function newMessageInternal(id, messageType, name, data, type, callbackType)
    local message = {
        id = id,
        messageType = messageType,
        name = name,
        data = data,
        type = type,
        callbackType = callbackType,
    }

    setmetatable(message, messageMetatable)

    return message
end

--- create a new message
---@param id string
---@param messageType string
---@param name string
---@param data any
---@return Rhodium.taskMessage
local function newMessage(id, messageType, name, data)
    return newMessageInternal(id, messageType, name, data, "message")
end

--- create a new callback
--- @param name string
--- @param data any
--- @param type callbackType
--- @return Rhodium.taskMessage
local function newCallback(name, data, type)
    assert(type == "error" or type == "timeout", "callback type must be 'error' or 'timeout'")

    return newMessageInternal(nil, nil, name, data, "callback", type)
end

function messageFunctions:pack()
    return {
        id = self.id,
        messageType = self.messageType,
        name = self.name,
        data = self.data,
        type = self.type,
        callbackType = self.callbackType,
    }
end

---@param data table
---@return Rhodium.taskMessage
local function unpackMessage(data)
    assert(data.name)
    assert(data.type)

    if data.type == "callback" then
        assert(data.callbackType)
    end

    assert(data.type == "message" or data.type == "callback" or data.type == "quit",
        "invalid message type: " .. data.type)

    return newMessageInternal(data.id, data.messageType, data.name, data.data, data.type, data.callbackType)
end

return {
    new = newMessage,
    newCallback = newCallback,
    unpack = unpackMessage,
}
