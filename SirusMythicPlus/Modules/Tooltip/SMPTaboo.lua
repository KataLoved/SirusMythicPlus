---@class SMPTaboo
local SMPTaboo = SMPLoader:CreateModule("SMPTaboo")
local private = SMPTaboo.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

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
private.ladderSafe = true

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
---@param lr number|nil left R
---@param lg number|nil left G
---@param lb number|nil left B
---@param rr number|nil right R
---@param rg number|nil right G
---@param rb number|nil right B
local function addPair(tt, left, right, lr, lg, lb, rr, rg, rb)
    if right and right ~= "" then
        tt:AddDoubleLine(left, right,
            lr or 1, lg or 0.82, lb or 0,
            rr or 1, rg or 1, rb or 1)
    end
end

local function hexToRGB(hex)
    if not hex then return 1, 1, 1 end
    hex = hex:gsub("|c", ""):gsub("|r", ""):gsub("^FF", ""):gsub("^ff", "")
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r / 255, g / 255, b / 255
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
---@return string|nil
local function formatRank(rank)
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

---@param playerName string
---@return number timed
---@return number total
local function getOtherRunStats(playerName)
    local mapsTable = C_ChallengeMode.GetMapTable()
    if not mapsTable or #mapsTable == 0 then return 0, 0 end

    local timed = 0
    local total = 0

    for i = 1, #mapsTable do
        local mapChallengeModeID = mapsTable[i]
        local statInfo = C_MythicPlus.GetPlayerStatsForMap(playerName, mapChallengeModeID)
        if statInfo and statInfo.level and statInfo.level > 0 then
            total = total + 1
            local _, _, timer = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
            if statInfo.durationSec and timer and statInfo.durationSec <= timer then
                timed = timed + 1
            end
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

---@return table<number, {name: string, level: number, duration: number, timer: number}>|nil
local function getLocalAllKeys()
    local mapScoreInfo = C_ChallengeMode.GetMapScoreInfo()
    if not mapScoreInfo then return nil end

    local result = {}
    for _, info in ipairs(mapScoreInfo) do
        local duration = 0
        local timer = 0
        if info.level and info.level > 0 then
            local inTimeInfo = C_MythicPlus.GetSeasonBestForMap(info.mapChallengeModeID)
            if inTimeInfo then
                duration = inTimeInfo.durationSec or 0
            end
            local _, _, t = C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID)
            timer = t or 0
        end
        result[#result + 1] = {
            name = info.name or "?",
            level = info.level or 0,
            duration = duration,
            timer = timer,
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
---@return table<number, {name: string, level: number, duration: number, timer: number}>|nil
local function getOtherAllKeys(playerName)
    local mapsTable = C_ChallengeMode.GetMapTable()
    if not mapsTable or #mapsTable == 0 then return nil end

    local result = {}

    for i = 1, #mapsTable do
        local mapChallengeModeID = mapsTable[i]
        local mapName = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
        local statInfo = C_MythicPlus.GetPlayerStatsForMap(playerName, mapChallengeModeID)
        local level = statInfo and statInfo.level or 0
        local duration = statInfo and statInfo.durationSec or 0
        local _, _, timer = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)

        result[#result + 1] = {
            name = mapName or "?",
            level = level,
            duration = duration,
            timer = timer or 0,
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
local function fmtDuration(sec)
    if not sec or sec == 0 then return nil end
    return math.floor(sec / 60) .. ":" .. string.format("%02d", sec % 60)
end

local function addDungeonList(tt, allKeys)
    if not allKeys or #allKeys == 0 then return end

    tt:AddLine(" ")

    for _, entry in ipairs(allKeys) do
        local left = "|cffffffff" .. entry.name .. "|r"
        local right = ""

        if entry.level > 0 then
            local dur = fmtDuration(entry.duration)
            local tmr = fmtDuration(entry.timer)
            if dur and tmr then
                right = "|cff808080(" .. dur .. "/" .. tmr .. ")|r "
            else
                right = "|cff808080(нет данных)|r "
            end
            right = right .. keyColor(entry.level) .. "+" .. entry.level .. "|r"
        else
            right = "|cff808080-|r"
        end

        tt:AddDoubleLine(left, right)
    end
end

---@param playerName string
---@return number|nil rank
local function getLadderRank(playerName)
    if not private.ladderSafe then return nil end
    if not C_Ladder or not C_Ladder.RequestSearch then return nil end

    local numResults = C_Ladder.GetNumSearchResults(MYTHIC_PLUS_BRACKET)
    if numResults and numResults > 0 then
        for i = 1, numResults do
            local rank, name = C_Ladder.GetSearchResultPlayerInfo(MYTHIC_PLUS_BRACKET, i)
            if name and name == playerName then
                return tonumber(rank)
            end
        end
    end

    local ok, err = pcall(function()
        C_Ladder.RequestSearch(MYTHIC_PLUS_BRACKET, playerName)
    end)

    if not ok then
        print("|cffff0000SMP|r: C_Ladder.RequestSearch error for '" .. tostring(playerName) .. "': " .. tostring(err))
    end

    return nil
end

---@param tt table
---@param unit string
local function renderTooltip(tt, unit)
    if not UnitIsPlayer(unit) then return end
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
            C_Timer:After(1, function()
                if SMPTaboo:IsShown() then
                    SMPTaboo:RefreshTooltip()
                end
            end)
            C_Timer:After(3, function()
                if SMPTaboo:IsShown() then
                    SMPTaboo:RefreshTooltip()
                end
            end)
        end
    end

    local rank = getLadderRank(name)
    local cfg = SMPConfig:GetProfileConfig("tooltip") or {}

    if cfg.showSeparator ~= false then
        tt:AddLine(" ")
    end

    local icon = ("|T%s:%d:%d:0:0|t "):format(MPLUS_ICON, ICON_SIZE, ICON_SIZE)
    tt:AddLine(icon .. "|cff00ff00Mythic+|r", 1, 1, 1)

    if C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetSeasonTimeLeft then
        local season, week = C_MythicPlus.GetCurrentSeason()
        local timeLeft = C_MythicPlus.GetSeasonTimeLeft()
        if season and week and timeLeft and timeLeft > 0 then
            local days = math.floor(timeLeft / 86400)
            local hours = math.floor(timeLeft % 86400 / 3600)
            local mins = math.floor(timeLeft % 3600 / 60)
            local secs = math.floor(timeLeft % 60)
            local timeStr = days .. "д " .. hours .. "ч " .. mins .. "м " .. secs .. "с"
            local leftStr = "|cffFFD100Сезон|r " .. season .. " |cff888888(Неделя " .. week .. "/12)|r"
            tt:AddDoubleLine(leftStr, timeStr, 1, 1, 1, 1, 1, 1)
        elseif season and week then
            local leftStr = "|cffFFD100Сезон|r " .. season .. " |cff888888(Неделя " .. week .. "/12)|r"
            tt:AddLine(leftStr, 1, 1, 1)
        else
            tt:AddLine("|cff888888Межсезонье|r", 1, 1, 1)
        end
    end

    local s = math.floor(score)
    tt:AddDoubleLine("Рейтинг M+", tostring(s), 1, 0.82, 0, hexToRGB(scoreColor(s)))

    if rank then
        local rankColor = "|cff808080"
        if rank <= 20 then rankColor = "|cffffd100"
        elseif rank <= 100 then rankColor = "|cffff8000"
        elseif rank <= 1000 then rankColor = "|cffa335ee"
        end
        tt:AddDoubleLine("Место в ладдере", tostring(rank), 1, 0.82, 0, hexToRGB(rankColor))
    end

    local keyText = fmtKey(bestLevel, bestDungeon)
    if keyText then
        tt:AddDoubleLine("Макс. ключ", keyText, 1, 0.82, 0, hexToRGB(keyColor(bestLevel)))
    elseif not isLocal and bestLevel == nil then
        tt:AddDoubleLine("Макс. ключ", "|cffffd100Загрузка...|r", 1, 0.82, 0, 1, 0.82, 0)
    else
        tt:AddDoubleLine("Макс. ключ", "-", 1, 0.82, 0, 0.5, 0.5, 0.5)
    end

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
                C_Timer:After(1, function()
                    if SMPTaboo:IsShown() then
                        SMPTaboo:RefreshTooltip()
                    end
                end)
                C_Timer:After(3, function()
                    if SMPTaboo:IsShown() then
                        SMPTaboo:RefreshTooltip()
                    end
                end)
            end
        end
        addDungeonList(tt, allKeys)
    else
        if isLocal then
            local timed, total = getLocalRunStats()
            if total > 0 then
                tt:AddDoubleLine("Забеги (в таймер/всего)", timed .. "/" .. total, 1, 0.82, 0, 1, 1, 1)
            end
        else
            local timed, total = getOtherRunStats(name)
            if total > 0 then
                tt:AddDoubleLine("Лучшее за сезон (в таймер/всего)", timed .. "/" .. total, 1, 0.82, 0, 1, 1, 1)
            else
                tt:AddDoubleLine("Лучшее за сезон", "|cffffd100Загрузка...|r", 1, 0.82, 0, 1, 0.82, 0)
                pcall(function()
                    C_MythicPlus.RequestPlayerStat(name)
                end)
                C_Timer:After(1, function()
                    if SMPTaboo:IsShown() then
                        SMPTaboo:RefreshTooltip()
                    end
                end)
                C_Timer:After(3, function()
                    if SMPTaboo:IsShown() then
                        SMPTaboo:RefreshTooltip()
                    end
                end)
            end
        end
    end
end

local seasonTicker = nil

local function stopSeasonTicker()
    if seasonTicker then
        seasonTicker:Cancel()
        seasonTicker = nil
    end
end

local function startSeasonTicker()
    stopSeasonTicker()
    seasonTicker = C_Timer:NewTicker(1, function()
        if SMPTaboo:IsShown() then
            SMPTaboo:RefreshTooltip()
        else
            stopSeasonTicker()
        end
    end)
end

local function onTooltipSetUnit(tt)
    if not private.isAvailable() then return end

    local _, unit = tt:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    private.currentTooltipGUID = UnitGUID(unit)
    renderTooltip(tt, unit)
    startSeasonTicker()
end

local function onTooltipCleared()
    private.currentTooltipGUID = nil
    stopSeasonTicker()
end

function private.isAvailable()
    return C_MythicPlus and C_MythicPlus.IsMythicPlusActive and C_MythicPlus.IsMythicPlusActive()
        and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
end

function private.testLadderSafety()
    if not C_Ladder or not C_Ladder.RequestSearch then
        private.ladderSafe = false
		SMP:Print("|cffff0000SMP|r: C_Ladder not available, ladder rank disabled")
        return
    end

	SMP:Print("|c00ff00SMP|r: Testing C_Ladder.RequestSearch...")

    local ok, err = pcall(function()
        C_Ladder.RequestSearch(MYTHIC_PLUS_BRACKET, "SMPTest")
    end)

    if ok then
        private.ladderSafe = true
		SMP:Print("|c00ff00SMP|r: C_Ladder.RequestSearch OK, ladder rank enabled")
    else
        private.ladderSafe = false
		SMP:Print("|cffff0000SMP|r: C_Ladder.RequestSearch FAILED.")
		SMP:Print("|cffff0000SMP|r: Ladder rank disabled")
    end
end

function private.patchLadderFrames()
    local frames = {
        "PVPLadderFrame",
        "RenegadeLadderFrame",
        "LadderDummyFrame",
        "LadderMythicPlusFrame",
    }

    for _, frameName in ipairs(frames) do
        local frame = _G[frameName]
        if frame and frame.Container and frame.Container.RightContainer
           and frame.Container.RightContainer.TopContainer then
            local top = frame.Container.RightContainer.TopContainer
            if not top.SearchFrame then
                top.SearchFrame = CreateFrame("Frame", nil, top)
                top.SearchFrame.SearchButton = CreateFrame("Button", nil, top.SearchFrame)
                top.SearchFrame.SearchButton.StartDelay = function() end
            end
            if not top.SearchButton then
                top.SearchButton = top.SearchFrame.SearchButton
            end
        end
    end
end

function SMPTaboo:Initialize()
    private.patchLadderFrames()
    C_Timer:After(2, function()
        private.testLadderSafety()
        if C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end
    end)
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
