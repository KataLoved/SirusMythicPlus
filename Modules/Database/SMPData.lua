---@class SMPData
local SMPData = SMPLoader:CreateModule("SMPData")
local private = SMPData.private

---@type SMPDataSchema
local SMPDataSchema = SMPLoader:ImportModule("SMPDataSchema")

---@type ThreadLib
local ThreadLib = SMPLoader:ImportModule("ThreadLib")

private.ladderData = {}
private.loaded = false
private.validated = false
private.validateTimer = nil

local VALIDATE_BATCH_SIZE = 500
local VALIDATE_DELAY = 0.1

---@param name string
---@return table|nil entry
function SMPData:LadderLookup(name)
    if not name then return nil end
    return private.ladderData[name]
end

---@param data table<string, table>
function SMPData:RegisterLadderData(data)
    if type(data) ~= "table" then return end
    private.ladderData = data
    private.loaded = true
    private.validated = false
    self:StartValidation()
end

---@return boolean
function SMPData:IsLoaded()
    return private.loaded
end

---@return boolean
function SMPData:IsValidated()
    return private.validated
end

function SMPData:StartValidation()
    if private.validated then return end
    if private.validateTimer then return end

    local queue = {}
    for name in pairs(private.ladderData) do
        queue[#queue + 1] = name
    end

    private.validateTimer = ThreadLib.ThreadCallback(function()
        while #queue > 0 do
            local count = 0
            while #queue > 0 and count < VALIDATE_BATCH_SIZE do
                local name = table.remove(queue)
                local entry = private.ladderData[name]
                if entry and not SMPDataSchema:ValidateEntry(entry) then
                    private.ladderData[name] = nil
                end
                count = count + 1
            end
            coroutine.yield()
        end
        private.validated = true
    end, VALIDATE_DELAY, function()
        private.validateTimer = nil
    end)
end
