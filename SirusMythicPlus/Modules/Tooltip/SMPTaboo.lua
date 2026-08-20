---@class SMPTaboo
local SMPTaboo = SMPLoader:CreateModule("SMPTaboo")
local private = SMPTaboo.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

---@type SMPLib
local SMPLib = SMPLoader:ImportModule("SMPLib")

---@type SMPRequest
local SMPRequest = SMPLoader:ImportModule("SMPRequest")

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

local MPLUS_ICON = "Interface\\Icons\\INV_Relics_Hourglass"
local ICON_SIZE = 14

local LABEL = { 1, 0.82, 0 }
local DIM = { 0.5, 0.5, 0.5 }

local DUNGEON_ABBREVIATIONS = {
    ["Аукенайские гробницы"] = "АГ",
    ["Бастионы Адского Пламени"] = "БАП",
    ["Гробницы Маны"] = "ГМ",
    ["Крепость Драк'Тарон"] = "КД'Т",
    ["Крепость Утгарда"] = "КУ",
    ["Крепость Утгард"] = "КУ",
    ["Кузня Крови"] = "КК",
    ["Пик Утгарда"] = "ПУ",
    ["Цитадель Утгарда"] = "ЦУ",
    ["Узилище"] = "У",
    ["Чертоги Молний"] = "ЧМ",
    ["Королевство Ан'кахет"] = "КА",
    ["Ан'кахет: Старое Королевство"] = "КА",
}

private.currentTooltipGUID = nil
private.currentTooltipName = nil
private.isRefreshing = false
private.liveCountdown = false

---@param name string|nil
---@return string
local function abbreviateDungeon(name)
    if not name then return "?" end

    name = tostring(name):gsub("%s*%(%d+%)%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")

    local cfg = SMPConfig:GetProfileConfig("tooltip") or {}
    if cfg.abbreviateDungeons then
        return DUNGEON_ABBREVIATIONS[name] or name
    end
    return name
end

---@param tt table
---@param left string
---@param right string|nil
---@param rightColor table|nil
local function addPair(tt, left, right, rightColor)
    if not right or right == "" then return end
    local c = rightColor or { 1, 1, 1 }
    tt:AddDoubleLine(left, right, LABEL[1], LABEL[2], LABEL[3], c[1], c[2], c[3])
end

---@param level number|nil
---@param dungeon string|nil
---@return string|nil
local function fmtKey(level, dungeon)
    level = tonumber(level)
    if not level or level == 0 then return nil end

    local color = SMPLib:KeyColor(level)
    if not dungeon or dungeon == "" then
        return (color .. "+%d|r"):format(level)
    end
    return (color .. "+%d|r  %s"):format(level, abbreviateDungeon(dungeon))
end

---@param sec number|nil
---@return string|nil
local function fmtDuration(sec)
    if not sec or sec == 0 then return nil end
    return math.floor(sec / 60) .. ":" .. string.format("%02d", sec % 60)
end

---@param seconds number
---@return string
local function fmtCountdown(seconds)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local mins = math.floor(seconds % 3600 / 60)
    local secs = math.floor(seconds % 60)
    return days .. "д " .. hours .. "ч " .. mins .. "м " .. secs .. "с"
end

---@param tt table
---@param dungeons table|nil
local function addDungeonList(tt, dungeons)
    if not dungeons or #dungeons == 0 then return end

    tt:AddLine(" ")

    for _, entry in ipairs(dungeons) do
        local left = "|cffffffff" .. abbreviateDungeon(entry.name) .. "|r"
        local right

        if entry.level > 0 then
            local duration = fmtDuration(entry.duration)
            local timer = fmtDuration(entry.timer)
            if duration and timer then
                right = "|cff808080(" .. duration .. "/" .. timer .. ")|r "
            else
                right = "|cff808080(нет данных)|r "
            end
            right = right .. SMPLib:KeyColor(entry.level) .. "+" .. entry.level .. "|r"
        else
            right = "|cff808080-|r"
        end

        tt:AddDoubleLine(left, right)
    end
end

---@param tt table
---@return boolean liveCountdown нужен ли посекундный тик
local function addSeasonLine(tt)
    if not (C_MythicPlus and C_MythicPlus.GetCurrentSeason) then return false end

    local season, week = C_MythicPlus.GetCurrentSeason()
    if not season or not week then
        tt:AddLine("|cff888888Межсезонье|r", 1, 1, 1)
        return false
    end

    local left = "|cffFFD100Сезон|r " .. season .. " |cff888888(Неделя " .. week .. "/12)|r"

    local timeLeft = C_MythicPlus.GetSeasonTimeLeft and C_MythicPlus.GetSeasonTimeLeft() or 0
    if timeLeft and timeLeft > 0 then
        tt:AddDoubleLine(left, fmtCountdown(timeLeft), 1, 1, 1, 1, 1, 1)
        private.seasonLineIndex = tt:NumLines()
        private.seasonLineText = left
        return true
    end

    tt:AddLine(left, 1, 1, 1)
    return false
end

---@param tt table
---@param name string
local function renderTooltipForLFGList(tt, name)
	if not name then return end

	local score = SMPRequest:GetMythicRating(name) or 0
    if score <= 0 then return end

    local stats, statsState = SMPRequest:GetPlayerStats(name)
    local rank = SMPRequest:GetLadderRank(name, false)

	local cfg = SMPConfig:GetProfileConfig("tooltip") or {}
    if cfg.showSeparator ~= false then
        tt:AddLine(" ")
    end

    local icon = ("|T%s:%d:%d:0:0|t "):format(MPLUS_ICON, ICON_SIZE, ICON_SIZE)
    tt:AddLine(icon .. "|cff00ff00Mythic+|r", 1, 1, 1)

    addSeasonLine(tt)

    local rounded = math.floor(score)
    addPair(tt, "Рейтинг M+", tostring(rounded), SMPLib:ScoreColorRGB(rounded))

    if rank then
        addPair(tt, "Место в ладдере", tostring(rank), SMPLib:RankColorRGB(rank))
    end

    local bestLevel = stats and stats.bestLevel
    local keyText = fmtKey(bestLevel, stats and stats.bestDungeon)
    if keyText then
        addPair(tt, "Макс. ключ", keyText, SMPLib:KeyColorRGB(bestLevel))
    else
        addPair(tt, "Макс. ключ", SMPRequest:GetStatusText(statsState) or "-", DIM)
    end

    if IsShiftKeyDown() or cfg.showDungeonListAlways then
        if stats then addDungeonList(tt, stats.dungeons) end
        return
    end

    if stats and stats.total > 0 then
        addPair(tt, "Лучшее за сезон (в таймер/всего)", stats.timed .. "/" .. stats.total)
    else
        addPair(tt, "Лучшее за сезон", SMPRequest:GetStatusText(statsState) or "-", DIM)
    end
end

---@param tt table
---@param unit string
---@return boolean liveCountdown
local function renderTooltip(tt, unit)
    private.seasonLineIndex = nil

    if not UnitIsPlayer(unit) then return false end
    if UnitIsEnemy("player", unit) then return false end

    local name = UnitName(unit)
    if not name then return false end

    local isLocal = UnitIsUnit(unit, "player")

    local score
    if isLocal then
        score = C_ChallengeMode.GetOverallDungeonScore() or 0
    else
        score = SMPRequest:GetMythicRating(unit) or 0
    end

    if score <= 0 then return false end

    local stats, statsState
    if isLocal then
        stats, statsState = SMPRequest:GetLocalStats()
    else
        stats, statsState = SMPRequest:GetPlayerStats(name)
    end

    local rank = SMPRequest:GetLadderRank(name, isLocal)

    local cfg = SMPConfig:GetProfileConfig("tooltip") or {}
    if cfg.showSeparator ~= false then
        tt:AddLine(" ")
    end

    local icon = ("|T%s:%d:%d:0:0|t "):format(MPLUS_ICON, ICON_SIZE, ICON_SIZE)
    tt:AddLine(icon .. "|cff00ff00Mythic+|r", 1, 1, 1)

    local liveCountdown = addSeasonLine(tt)

    local rounded = math.floor(score)
    addPair(tt, "Рейтинг M+", tostring(rounded), SMPLib:ScoreColorRGB(rounded))

    if rank then
        addPair(tt, "Место в ладдере", tostring(rank), SMPLib:RankColorRGB(rank))
    end

    local bestLevel = stats and stats.bestLevel
    local keyText = fmtKey(bestLevel, stats and stats.bestDungeon)
    if keyText then
        addPair(tt, "Макс. ключ", keyText, SMPLib:KeyColorRGB(bestLevel))
    else
        addPair(tt, "Макс. ключ", SMPRequest:GetStatusText(statsState) or "-", DIM)
    end

    if IsShiftKeyDown() or cfg.showDungeonListAlways then
        if stats then
            addDungeonList(tt, stats.dungeons)
        end
        return liveCountdown
    end

    if isLocal then
        local timed, total = SMPRequest:GetLocalRunStats()
        if total > 0 then
            addPair(tt, "Забеги (в таймер/всего)", timed .. "/" .. total)
        end
    elseif stats and stats.total > 0 then
        addPair(tt, "Лучшее за сезон (в таймер/всего)", stats.timed .. "/" .. stats.total)
    else
        addPair(tt, "Лучшее за сезон", SMPRequest:GetStatusText(statsState) or "-", DIM)
    end

    return liveCountdown
end

local seasonTicker = nil

local function stopSeasonTicker()
    if seasonTicker then
        seasonTicker:Cancel()
        seasonTicker = nil
    end
end

function private.clearState()
    private.currentTooltipGUID = nil
	private.currentTooltipName = nil
    private.liveCountdown = false
    private.seasonLineIndex = nil
    stopSeasonTicker()
end

---@return boolean
function private.isHovered()
    if not private.currentTooltipGUID and not private.currentTooltipName then return false end

    if private.currentTooltipGUID then
        if UnitExists("mouseover") and UnitGUID("mouseover") == private.currentTooltipGUID then
            return true
        end

        local owner = GameTooltip:GetOwner()
        if owner and owner ~= UIParent and owner.IsMouseOver then
            return owner:IsMouseOver() == true
        end
    end

    if private.currentTooltipName then
        local leftText = _G["GameTooltipTextLeft1"]
        return leftText and leftText:GetText() == private.currentTooltipName
    end

    return false
end

---@return boolean
local function updateSeasonCountdown()
    local index = private.seasonLineIndex
    if not index then return false end

    local leftText = _G["GameTooltipTextLeft" .. index]
    local rightText = _G["GameTooltipTextRight" .. index]
    if not leftText or not rightText then return false end
    if leftText:GetText() ~= private.seasonLineText then return false end

    local timeLeft = C_MythicPlus.GetSeasonTimeLeft and C_MythicPlus.GetSeasonTimeLeft() or 0
    if not timeLeft or timeLeft <= 0 then return false end

    rightText:SetText(fmtCountdown(timeLeft))
    return true
end

local function startSeasonTicker()
    stopSeasonTicker()
    seasonTicker = C_Timer:NewTicker(1, function()
        if not GameTooltip:IsShown() or not private.isHovered() then
            private.clearState()
            return
        end
        if not updateSeasonCountdown() then
            stopSeasonTicker()
        end
    end)
end

local function onTooltipSetUnit(tt)
    if not private.isAvailable() then return end

    local _, unit = tt:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    private.currentTooltipGUID = UnitGUID(unit)
    private.liveCountdown = renderTooltip(tt, unit)

    if private.liveCountdown then
        startSeasonTicker()
    else
        stopSeasonTicker()
    end
end

local function onTooltipCleared()
    if private.isRefreshing then return end
    private.clearState()
end

---@return boolean
function private.isAvailable()
    return C_MythicPlus and C_MythicPlus.IsMythicPlusActive and C_MythicPlus.IsMythicPlusActive()
        and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor ~= nil
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

    SMPRequest:Subscribe(function()
        if SMPTaboo:IsShown() then
            SMPTaboo:RefreshTooltip()
        end
    end)

    GameTooltip:HookScript("OnTooltipSetUnit", onTooltipSetUnit)
    GameTooltip:HookScript("OnTooltipCleared", onTooltipCleared)
    GameTooltip:HookScript("OnHide", onTooltipCleared)

	hooksecurefunc("LFGListApplicantMember_OnEnter", function(self)
        local applicantID = self:GetParent().applicantID
        local memberIdx = self.memberIdx

        if not applicantID or not memberIdx then return end

        local name = C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
        if not name then return end

		local activeEntryInfo = C_LFGList.GetActiveEntryInfo()
		if activeEntryInfo then
			local activityInfo = C_LFGList.GetActivityInfoTable(activeEntryInfo.activityID)
			if not activityInfo or not activityInfo.isMythicPlusActivity then return end
		end

        if SMPRequest:GetMythicRating(name) then
            private.currentTooltipName = name
            renderTooltipForLFGList(GameTooltip, name)
        end
    end)
end

---@return boolean
function SMPTaboo:IsShown()
    return private.currentTooltipGUID ~= nil or private.currentTooltipName ~= nil
end

function SMPTaboo:RefreshTooltip()
    if private.isRefreshing then return end

    if not GameTooltip:IsShown() then
        private.clearState()
        return
    end

    if private.currentTooltipGUID then
        local _, tooltipUnit = GameTooltip:GetUnit()
        if not tooltipUnit or not UnitExists(tooltipUnit)
           or UnitGUID(tooltipUnit) ~= private.currentTooltipGUID
           or not private.isHovered()
        then
            private.clearState()
            return
        end

        private.isRefreshing = true
        local ok, err = pcall(GameTooltip.SetUnit, GameTooltip, tooltipUnit)
        private.isRefreshing = false

        if not ok then
            SMPDebug:Log("ERROR", "[SMPTaboo] RefreshTooltip: " .. tostring(err))
        end
    end

    if private.currentTooltipName then
        local leftText = _G["GameTooltipTextLeft1"]
        if not leftText or leftText:GetText() ~= private.currentTooltipName then
            private.clearState()
            return
        end

        private.isRefreshing = true
        local ok = pcall(renderTooltipForLFGList, GameTooltip, private.currentTooltipName)
        private.isRefreshing = false

        if not ok then
            SMPDebug:Log("ERROR", "[SMPTaboo] RefreshTooltip: " .. tostring(err))
        end
    end
end