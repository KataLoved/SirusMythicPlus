---@class SMPForcesData
local SMPForcesData = SMPLoader:CreateModule("SMPForcesData")
local private = SMPForcesData.private

private.data = {}
private.loaded = false

---@param areaID number
---@return number total
function SMPForcesData:GetTotal(areaID)
    local d = private.data[areaID]
    return d and d.total or 900
end

---@param areaID number
---@param npcID number
---@return number count
function SMPForcesData:GetCount(areaID, npcID)
    local d = private.data[areaID]
    if d and d.mobs and d.mobs[npcID] then
        return d.mobs[npcID].count or 0
    end
    return 0
end

---@param npcID number
---@return number count, number areaID
function SMPForcesData:LookupByNPC(npcID)
    for areaID, d in pairs(private.data) do
        if d.mobs and d.mobs[npcID] then
            return d.mobs[npcID].count or 0, areaID
        end
    end
    return 0, 0
end

---@return boolean
function SMPForcesData:IsLoaded()
    return private.loaded
end

---@param data table<number, table>
function SMPForcesData:RegisterData(data)
    if type(data) ~= "table" then return end
    private.data = data
    private.loaded = true
end
