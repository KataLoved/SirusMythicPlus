---@class ThreadLib
local ThreadLib = SMPLoader:CreateModule("ThreadLib")

local coStatus = coroutine.status
local coResume = coroutine.resume
local coCreate = coroutine.create
local newTicker = C_Timer.NewTicker

---@param threadFunction function
---@param delay number
---@param errorMessage string|nil
---@param callbackFunction function|nil
---@return table timer
---@return thread thread
function ThreadLib.Thread(threadFunction, delay, errorMessage, callbackFunction)
    if type(threadFunction) ~= "function" then
        error("ThreadLib.Thread: threadFunction must be a function", 2)
    end
    if type(delay) ~= "number" then
        error("ThreadLib.Thread: delay must be a number", 2)
    end

    local thread = coCreate(threadFunction)
    local timer
    timer = newTicker(delay, function()
        if coStatus(thread) == "suspended" then
            local success, ret = coResume(thread)
            if not success then
                timer:Cancel()
            end
        elseif coStatus(thread) == "dead" then
            timer:Cancel()
            if callbackFunction then
                callbackFunction()
            end
        end
    end)
    return timer, thread
end

function ThreadLib.ThreadCallback(threadFunction, delay, callbackFunction)
    return ThreadLib.Thread(threadFunction, delay, nil, callbackFunction)
end

function ThreadLib.ThreadSimple(threadFunction, delay)
    return ThreadLib.Thread(threadFunction, delay)
end
