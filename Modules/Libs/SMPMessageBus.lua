---@class SMPMessageBus
local SMPMessageBus = setmetatable(
    SMPLoader:CreateModule("SMPMessageBus"),
    { __call = function(self) return self.New() end }
)

local insert = table.insert
local wipe = wipe

---@return SMPMessageBusInstance
function SMPMessageBus.New()
    ---@class SMPMessageBusInstance
    local bus = {}

    ---@type table<string, function[]>
    bus.repeatEvents = {}
    ---@type table<string, function[]>
    bus.onceEvents = {}
    ---@type table<string, boolean>
    bus.executing = {}

    local function fire(eventName, ...)
        if bus.executing[eventName] then
            error("SMPMessageBus: event '" .. eventName .. "' is already being executed", 2)
        end

        bus.executing[eventName] = true

        if bus.onceEvents[eventName] then
            local eventList = bus.onceEvents[eventName]
            for i = 1, #eventList do
                eventList[i](...)
            end
            wipe(eventList)
        end

        if bus.repeatEvents[eventName] then
            local eventList = bus.repeatEvents[eventName]
            for i = 1, #eventList do
                eventList[i](...)
            end
        end

        bus.executing[eventName] = nil
    end

    function bus:Fire(eventName, ...)
        return fire(eventName, ...)
    end

    function bus:RegisterRepeating(eventName, callback)
        if type(callback) ~= "function" then
            error("SMPMessageBus:RegisterRepeating: callback must be a function", 2)
        end
        if type(eventName) ~= "string" then
            error("SMPMessageBus:RegisterRepeating: eventName must be a string", 2)
        end
        if not self.repeatEvents[eventName] then
            self.repeatEvents[eventName] = {}
        end
        insert(self.repeatEvents[eventName], callback)
    end

    function bus:RegisterOnce(eventName, callback)
        if type(callback) ~= "function" then
            error("SMPMessageBus:RegisterOnce: callback must be a function", 2)
        end
        if type(eventName) ~= "string" then
            error("SMPMessageBus:RegisterOnce: eventName must be a string", 2)
        end
        if not self.onceEvents[eventName] then
            self.onceEvents[eventName] = {}
        end
        insert(self.onceEvents[eventName], callback)
    end

    function bus:UnregisterRepeating(eventName, callback)
        local eventList = self.repeatEvents[eventName]
        if not eventList then return end
        for i = #eventList, 1, -1 do
            if eventList[i] == callback then
                table.remove(eventList, i)
            end
        end
    end

    function bus:UnregisterAll(eventName)
        if self.repeatEvents[eventName] then
            wipe(self.repeatEvents[eventName])
        end
        if self.onceEvents[eventName] then
            wipe(self.onceEvents[eventName])
        end
    end

    return bus
end

SMPMessageBus.shared = SMPMessageBus:New()
