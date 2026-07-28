---@class SMPSplitsData
local SMPSplitsData = SMPLoader:CreateModule("SMPSplitsData")
local private = SMPSplitsData.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

function SMPSplitsData:GetBest(mapId, level)
    local db = SMPConfig:GetGlobalConfig("splits")
    if not db or not db[mapId] then return nil end
    return db[mapId][level]
end

function SMPSplitsData:GetBestWithFallback(mapId, level, fallbackBehavior)
    local best = self:GetBest(mapId, level)
    if best then return best end

    local db = SMPConfig:GetGlobalConfig("splits")
    if not db or not db[mapId] then return nil end

    if fallbackBehavior == "none" then
        return nil
    elseif fallbackBehavior == "highest" then
        local highest = nil
        for _, entry in pairs(db[mapId]) do
            if not highest or entry.totalTime < highest.totalTime then
                highest = entry
            end
        end
        return highest
    elseif fallbackBehavior == "closest_higher" then
        local closest = nil
        local closestLevel = nil
        for lvl, entry in pairs(db[mapId]) do
            if lvl > level and (not closestLevel or lvl < closestLevel) then
                closest = entry
                closestLevel = lvl
            end
        end
        return closest
    elseif fallbackBehavior == "closest_lower" then
        local closest = nil
        local closestLevel = nil
        for lvl, entry in pairs(db[mapId]) do
            if lvl < level and (not closestLevel or lvl > closestLevel) then
                closest = entry
                closestLevel = lvl
            end
        end
        return closest
    elseif fallbackBehavior == "lowest" then
        local lowest = nil
        for _, entry in pairs(db[mapId]) do
            if not lowest or entry.totalTime > lowest.totalTime then
                lowest = entry
            end
        end
        return lowest
    end

    return nil
end

function SMPSplitsData:SaveRun(mapId, level, bossTimes, totalTime)
    local db = SMPConfig:GetGlobalConfig("splits")
    if not db then
        SMPConfig:UpdateGlobalConfig("splits", {})
        db = SMPConfig:GetGlobalConfig("splits")
    end

    if not db[mapId] then db[mapId] = {} end

    local existing = db[mapId][level]
    if not existing or totalTime < existing.totalTime then
        db[mapId][level] = {
            bossTimes = CopyTable(bossTimes),
            totalTime = totalTime,
        }
        return true
    end
    return false
end

return SMPSplitsData
