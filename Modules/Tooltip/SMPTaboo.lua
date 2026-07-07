---@class SMPTaboo
local SMPTaboo = SMPLoader:CreateModule("SMPTaboo")
local private = SMPTaboo.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

---@type SMPData
local SMPData = SMPLoader:ImportModule("SMPData")

local MPLUS_ICON = "Interface\\Icons\\INV_Relics_Hourglass"
local ICON_SIZE = 14
local SCORE_MIN = 0
local SCORE_MAX = 2500
local MYTHIC_PLUS_BRACKET = Enum.LadderBracketType.MYTHIC_PLUS

local DUNGEON_ABBREVIATIONS = {
    ["Аукенайские гробницы"] = "АГ",
    ["Бастионы Адского Пламени"] = "БАП",
    ["Гробницы Маны"] = "ГМ",
    ["Крепость Драк'Тарон"] = "КД'Т",
    ["Крепость Утгард"] = "КУ",
    ["Кузня Крови"] = "КК",
    ["Узилище"] = "У",
    ["Чертоги Молний"] = "ЧМ",
    ["Королевство Ан'кахет"] = "КА",
}

local SCORE_STOPS = {
    { 0.00, 0.12, 0.80, 0.20 },
    { 0.35, 0.00, 0.44, 0.87 },
    { 0.65, 0.64, 0.21, 0.93 },
    { 1.00, 1.00, 0.50, 0.00 },
}

private.currentTooltipGUID = nil
private.isRefreshing = false

---@param x number
---@param a number
---@param b number
---@return number
local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

---@param a number
---@param b number
---@param t number
---@return number
local function lerp(a, b, t)
    return a + (b - a) * t
end

---@param x number
---@return number
local function toByte01(x)
    x = clamp(x, 0, 1)
    return math.floor(x * 255 + 0.5)
end

---@param r number
---@param g number
---@param b number
---@return string
local function rgbToHex(r, g, b)
    return ("|cff%02x%02x%02x"):format(toByte01(r), toByte01(g), toByte01(b))
end

---@param name string
---@return string
local function abbreviateDungeon(name)
    if not name then return "?" end
    local cfg = SMPConfig:GetProfileConfig("tooltip") or {}
    if cfg.abbreviateDungeons then
        return DUNGEON_ABBREVIATIONS[name] or name
    end
    return name
end

---@param tt table
---@param left string
---@param right string
local function addPair(tt, left, right)
    if right and right ~= "" then
        tt:AddDoubleLine(left, right, 1, 0.82, 0, 1, 1, 1)
    end
end

---@param level number
---@return string
local function keyColor(level)
    level = tonumber(level or 0) or 0
    if level >= 15 then
        return "|cffffd100"
    elseif level >= 10 then
        return "|cffa335ee"
    else
        return "|cff0070dd"
    end
end

---@param level number|nil
---@param dungeon string|nil
---@return string|nil
local function fmtKey(level, dungeon)
    if not level or level == 0 then return nil end
    level = tonumber(level)
    if not level then return nil end

    local c = keyColor(level)
    local reset = "|r"

    if not dungeon or dungeon == "" then
        return (c .. "+%d" .. reset):format(level)
    end

    dungeon = abbreviateDungeon(tostring(dungeon):gsub("%s*%(%d+%)%s*$", ""))
    return (c .. "+%d" .. reset .. "  %s"):format(level, dungeon)
end

---@param score number
---@return string
local function scoreColor(score)
    score = tonumber(score or 0) or 0

    local t = 0
    if SCORE_MAX > SCORE_MIN then
        t = (score - SCORE_MIN) / (SCORE_MAX - SCORE_MIN)
    end

    t = clamp(t, 0, 1)

    local prev = SCORE_STOPS[1]
    for i = 2, #SCORE_STOPS do
        local cur = SCORE_STOPS[i]
        if t <= cur[1] then
            local span = cur[1] - prev[1]
            local lt = (span > 0) and ((t - prev[1]) / span) or 0

            local r = lerp(prev[2], cur[2], lt)
            local g = lerp(prev[3], cur[3], lt)
            local b = lerp(prev[4], cur[4], lt)

            return rgbToHex(r, g, b)
        end
        prev = cur
    end

    local last = SCORE_STOPS[#SCORE_STOPS]
    return rgbToHex(last[2], last[3], last[4])
end

---@param rank number
---@return string
local function formatRank(rank)
    rank = tonumber(rank)
    if not rank then return nil end

    if rank <= 20 then
        return "|cffffd100" .. rank .. "|r"
    elseif rank <= 100 then
        return "|cffff8000" .. rank .. "|r"
    elseif rank <= 1000 then
        return "|cffa335ee" .. rank .. "|r"
    else
        return tostring(rank)
    end
end

---@return number timed
---@return number total
local function getLocalRunStats()
    local runs = C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(true, true)
    if not runs then return 0, 0 end

    local timed = 0
    local total = #runs
    for _, run in ipairs(runs) do
        if run.completed then
            timed = timed + 1
        end
    end
    return timed, total
end

---@return number|nil bestLevel
---@return string|nil bestDungeon
local function findLocalBestKey()
    local mapScoreInfo = C_ChallengeMode.GetMapScoreInfo()
    if not mapScoreInfo then return nil, nil end

    local bestLevel = 0
    local bestDungeon = nil

    for _, info in ipairs(mapScoreInfo) do
        if info.level and info.level > bestLevel then
            bestLevel = info.level
            bestDungeon = info.name
        end
    end

    if bestLevel > 0 then
        return bestLevel, bestDungeon
    end
    return nil, nil
end

---@return table<number, {name: string, level: number}>|nil
local function getLocalAllKeys()
    local mapScoreInfo = C_ChallengeMode.GetMapScoreInfo()
    if not mapScoreInfo then return nil end

    local result = {}
    for _, info in ipairs(mapScoreInfo) do
        result[#result + 1] = {
            name = info.name or "?",
            level = info.level or 0,
        }
    end

    table.sort(result, function(a, b)
        if a.level == b.level then
            return a.name < b.name
        end
        return a.level > b.level
    end)

    return result
end

---@param playerName string
---@return number|nil bestLevel
---@return string|nil bestDungeon
local function findOtherBestKey(playerName)
    local mapsTable = C_ChallengeMode.GetMapTable()
    if not mapsTable or #mapsTable == 0 then return nil, nil end

    local bestLevel = 0
    local bestDungeon = nil

    for i = 1, #mapsTable do
        local mapChallengeModeID = mapsTable[i]
        local mapName = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
        local statInfo = C_MythicPlus.GetPlayerStatsForMap(playerName, mapChallengeModeID)

        if statInfo and statInfo.level and statInfo.level > bestLevel then
            bestLevel = statInfo.level
            bestDungeon = mapName
        end
    end

    if bestLevel > 0 then
        return bestLevel, bestDungeon
    end
    return nil, nil
end

---@param playerName string
---@return table<number, {name: string, level: number}>|nil
local function getOtherAllKeys(playerName)
    local mapsTable = C_ChallengeMode.GetMapTable()
    if not mapsTable or #mapsTable == 0 then return nil end

    local result = {}

    for i = 1, #mapsTable do
        local mapChallengeModeID = mapsTable[i]
        local mapName = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
        local statInfo = C_MythicPlus.GetPlayerStatsForMap(playerName, mapChallengeModeID)
        local level = statInfo and statInfo.level or 0

        result[#result + 1] = {
            name = mapName or "?",
            level = level,
        }
    end

    table.sort(result, function(a, b)
        if a.level == b.level then
            return a.name < b.name
        end
        return a.level > b.level
    end)

    return result
end

---@param tt table
---@param allKeys table
local function addDungeonList(tt, allKeys)
    if not allKeys or #allKeys == 0 then return end

    tt:AddLine(" ")

    for _, entry in ipairs(allKeys) do
        local left = "|cffffffff" .. entry.name .. "|r"
        local right

        if entry.level > 0 then
            right = keyColor(entry.level) .. "+" .. entry.level .. "|r"
        else
            right = "|cff808080-|r"
        end

        tt:AddDoubleLine(left, right)
    end
end

---@param playerName string
---@return number|nil rank
local function getLadderRank(playerName)
    if not C_Ladder or not C_Ladder.RequestSearch then return nil end

    local numResults = C_Ladder.GetNumSearchResults(MYTHIC_PLUS_BRACKET)
    if numResults and numResults > 0 then
        for i = 1, numResults do
            local rank, name = C_Ladder.GetSearchResultPlayerInfo(MYTHIC_PLUS_BRACKET, i)
            if name and name == playerName then
                return rank
            end
        end
    end

    C_Ladder.RequestSearch(MYTHIC_PLUS_BRACKET, playerName)
    return nil
end

---@param tt table
---@param unit string
local function renderTooltip(tt, unit)
    if UnitIsEnemy("player", unit) then return end

    local name = UnitName(unit)
    if not name then return end

    local isLocal = UnitIsUnit(unit, "player")

    local score = 0
    if isLocal then
        local dungeonScore = C_ChallengeMode.GetOverallDungeonScore()
        if C_GlobalStorage and C_GlobalStorage.GetVar then
            local scoreData = C_GlobalStorage.GetVar("ASMSG_MYTHIC_PLUS_PLAYER_SCORE")
            if scoreData and dungeonScore == nil then
                dungeonScore = scoreData.dungeonScore
            end
        end
        score = dungeonScore or 0
    else
        local mythicRating = C_Inspect and C_Inspect.GetMythicRating and C_Inspect.GetMythicRating(unit)
        score = mythicRating or 0
    end

    if score <= 0 then return end

    local bestLevel, bestDungeon
    if isLocal then
        bestLevel, bestDungeon = findLocalBestKey()
        if not bestLevel and C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end
    else
        bestLevel, bestDungeon = findOtherBestKey(name)
        if not bestLevel and C_MythicPlus.RequestPlayerStat then
            C_MythicPlus.RequestPlayerStat(name)
        end
    end

    local rank = getLadderRank(name)
    local ladderEntry = SMPData:LadderLookup(name)
    local cfg = SMPConfig:GetProfileConfig("tooltip") or {}

    if cfg.showSeparator ~= false then
        tt:AddLine(" ")
    end

    local icon = ("|T%s:%d:%d:0:0|t "):format(MPLUS_ICON, ICON_SIZE, ICON_SIZE)
    tt:AddLine(icon .. "|cff00ff00Mythic+|r", 1, 1, 1)

    local s = math.floor(score)
    addPair(tt, "Рейтинг M+", scoreColor(s) .. tostring(s) .. "|r")

    if rank then
        addPair(tt, "Место в ладдере", formatRank(rank) or tostring(rank))
    elseif ladderEntry and ladderEntry.rank then
        addPair(tt, "Место в ладдере", formatRank(ladderEntry.rank) or tostring(ladderEntry.rank))
    end

    addPair(tt, "Макс. ключ", fmtKey(bestLevel, bestDungeon) or "-")

    local showDungeonList = IsShiftKeyDown() or cfg.showDungeonListAlways
    if showDungeonList then
        local allKeys
        if isLocal then
            allKeys = getLocalAllKeys()
            if not allKeys and C_MythicPlus.RequestMapInfo then
                C_MythicPlus.RequestMapInfo()
            end
        else
            allKeys = getOtherAllKeys(name)
            if not allKeys and C_MythicPlus.RequestPlayerStat then
                C_MythicPlus.RequestPlayerStat(name)
            end
        end
        addDungeonList(tt, allKeys)
    else
        if isLocal then
            local timed, total = getLocalRunStats()
            if total > 0 then
                addPair(tt, "Забеги (в таймер/всего)", tostring(timed) .. "/" .. tostring(total))
            end
        elseif ladderEntry then
            if ladderEntry.timed or ladderEntry.total then
                addPair(tt, "Забеги (в таймер/всего)",
                    tostring(ladderEntry.timed or "-") .. "/" .. tostring(ladderEntry.total or "—"))
            end
        end
    end
end

local function onTooltipSetUnit(tt)
    if not private.isAvailable() then return end

    local ok = pcall(function()
        local _, unit = tt:GetUnit()
        if not unit or not UnitIsPlayer(unit) then return end

        private.currentTooltipGUID = UnitGUID(unit)
        renderTooltip(tt, unit)
    end)

    if not ok then
        tt:AddLine("|cffff0000SirusMythicPlus error|r")
    end
end

local function onTooltipCleared()
    private.currentTooltipGUID = nil
end

function private.isAvailable()
    return C_MythicPlus and C_MythicPlus.IsMythicPlusActive and C_MythicPlus.IsMythicPlusActive()
        and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
end

function SMPTaboo:Initialize()
    GameTooltip:HookScript("OnTooltipSetUnit", onTooltipSetUnit)
    GameTooltip:HookScript("OnTooltipCleared", onTooltipCleared)
end

---@return boolean
function SMPTaboo:IsShown()
    return private.currentTooltipGUID ~= nil
end

function SMPTaboo:RefreshTooltip()
    if private.isRefreshing or not private.currentTooltipGUID then return end
    if not GameTooltip:IsShown() then return end

    local _, tooltipUnit = GameTooltip:GetUnit()
    if not tooltipUnit or not UnitExists(tooltipUnit) then return end
    if UnitGUID(tooltipUnit) ~= private.currentTooltipGUID then return end

    private.isRefreshing = true
    GameTooltip:SetUnit(tooltipUnit)
    private.isRefreshing = nil
end
