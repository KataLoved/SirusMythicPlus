---@class SMPDataSchema
local SMPDataSchema = SMPLoader:CreateModule("SMPDataSchema")

---@param entry table
---@return boolean valid
function SMPDataSchema:ValidateEntry(entry)
    if type(entry) ~= "table" then return false end
    if entry.score ~= nil and type(entry.score) ~= "number" then return false end
    if entry.rank ~= nil and type(entry.rank) ~= "number" then return false end
    if entry.bestLevel ~= nil and type(entry.bestLevel) ~= "number" then return false end
    if entry.timed ~= nil and type(entry.timed) ~= "number" then return false end
    if entry.total ~= nil and type(entry.total) ~= "number" then return false end
    return true
end
