---@class SMPPlayerSearch
local SMPPlayerSearch = SMPLoader:CreateModule("SMPPlayerSearch")
local private = SMPPlayerSearch.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

---@type SMPLib
local SMPLib = SMPLoader:ImportModule("SMPLib")

private.pendingSearch = nil
private.searchResults = {}
private.selectedPlayer = nil

local MYTHIC_PLUS_BRACKET = 9
local MAX_RETRIES = 5

local BRAND = { r = 0.09, g = 0.52, b = 0.82 }
local BG_PANEL = { 0.05, 0.05, 0.08, 0.92 }
local BG_CARD = { 0.08, 0.08, 0.12, 0.85 }
local BG_ACTIVE = { 0.1, 0.14, 0.2, 0.95 }
local BORDER_NORMAL = { 0.35, 0.35, 0.4, 0.6 }
local BORDER_ACTIVE = { BRAND.r, BRAND.g, BRAND.b, 1 }

local CLASS_COLORS = {
    [1] = "ffc79c6e", [2] = "fff58cba", [3] = "ffabd473", [4] = "fffff569",
    [5] = "ffffffff", [6] = "ffc79c6e", [7] = "ff0070de", [8] = "ff69ccf0",
    [9] = "ff9482c9", [11] = "ffff7d0a",
}

local function classColor(id) return CLASS_COLORS[id] or "ffffffff" end

local function formatDuration(sec)
    if not sec or sec == 0 then return "-" end
    return math.floor(sec / 60) .. ":" .. string.format("%02d", sec % 60)
end

local function keyColor(level)
    level = tonumber(level or 0) or 0
    if level >= 15 then return "|cffffd100"
    elseif level >= 10 then return "|cffa335ee"
    else return "|cff0070dd"
    end
end

local function formatRank(rank)
    if not rank then return "" end
    if rank <= 20 then return "|cffffd100#" .. rank .. "|r"
    elseif rank <= 100 then return "|cffff8000#" .. rank .. "|r"
    elseif rank <= 1000 then return "|cffa335ee#" .. rank .. "|r"
    else return "|cff808080#" .. rank .. "|r"
    end
end

local function getSearchResults()
    local results = {}
    if not C_Ladder or not C_Ladder.GetNumSearchResults then return results end
    local num = C_Ladder.GetNumSearchResults(MYTHIC_PLUS_BRACKET)
    if not num or num == 0 then return results end
    for i = 1, num do
        local rank, name, _, classID, _, _, _, score = C_Ladder.GetSearchResultPlayerInfo(MYTHIC_PLUS_BRACKET, i)        if name then
            results[#results + 1] = { index = i, rank = rank, name = name, classID = classID, score = score or 0 }
        end
    end
    return results
end

local function buildPlayerDetail(playerName)
    local lines = {}
    local mapsTable = C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    local bestLevel, bestDungeon, timed, total = 0, "", 0, 0

    if mapsTable then
        for _, mapId in ipairs(mapsTable) do
            local mapName = C_ChallengeMode.GetMapUIInfo(mapId)
            local statInfo = C_MythicPlus.GetPlayerStatsForMap(playerName, mapId)
            if statInfo and statInfo.level and statInfo.level > 0 then
                local level = statInfo.level
                local duration = statInfo.durationSec or 0
                if level > bestLevel then bestLevel = level; bestDungeon = mapName or "?" end
                total = total + 1
                local _, _, timer = C_ChallengeMode.GetMapUIInfo(mapId)
                local isTimed = duration > 0 and timer and duration <= timer
                if isTimed then timed = timed + 1 end
                lines[#lines + 1] = {
                    name = mapName or "?", level = level,
                    duration = duration, timer = timer or 0,
                    timed = isTimed,
                }
            end
        end
    end

    table.sort(lines, function(a, b) return a.level > b.level end)
    return lines, bestLevel, bestDungeon, timed, total
end

function SMPPlayerSearch:Initialize()
end

function private:ShowCopyDialog(url)
    if not private.copyFrame then
        local f = CreateFrame("Frame", "SMPCopyDialog", UIParent)
        f:SetSize(420, 70)
        f:SetFrameStrata("TOOLTIP")
        f:SetClampedToScreen(true)
        f:EnableKeyboard(true)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        label:SetPoint("TOPLEFT", 10, -8)
        label:SetText("Ссылка на профиль — Ctrl+C для копирования")
        label:SetTextColor(0.7, 0.7, 0.7)

        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(390, 20)
        eb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        eb:SetFont("Fonts\\ARIALN.TTF", 11, "")
        eb:SetTextColor(1, 1, 1)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)

        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(eb)
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 1)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
            end
        end)

        private.copyFrame = f
        private.copyEditBox = eb
    end

    if private.aceFrame and private.aceFrame.frame then
        local anchor = private.aceFrame.frame
        private.copyFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    end

    private.copyEditBox:SetText(url)
    private.copyFrame:Show()
    private.copyEditBox:SetFocus()
    private.copyEditBox:HighlightText()
end

function SMPPlayerSearch:CreateFrame()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("|cff1784d1SMP|r — Поиск игрока")
    frame:SetWidth(480)
    frame:SetHeight(580)
    frame:SetLayout("Flow")
    frame:EnableResize(false)

    local searchRow = AceGUI:Create("SimpleGroup")
    searchRow:SetFullWidth(true)
    searchRow:SetLayout("Flow")
    frame:AddChild(searchRow)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel(nil)
    editBox:SetRelativeWidth(0.72)
    editBox:DisableButton(true)
    editBox:SetCallback("OnEnterPressed", function(_, _, text) private:Search(text) end)
    if editBox.editbox then
        editBox.editbox:SetScript("OnEnterPressed", function(self) private:Search(self:GetText()) end)
    end
    searchRow:AddChild(editBox)

    local searchBtn = AceGUI:Create("Button")
    searchBtn:SetText("Поиск")
    searchBtn:SetRelativeWidth(0.26)
    searchBtn:SetCallback("OnClick", function() private:Search(editBox:GetText()) end)
    searchRow:AddChild(searchBtn)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    frame:AddChild(scroll)

    private.aceFrame = frame
    private.editBox = editBox
    private.scroll = scroll

    frame:SetCallback("OnClose", function()
        if private.copyFrame then
            private.copyFrame:Hide()
        end
    end)

    local wowFrame = frame.frame
    if wowFrame then
        wowFrame:EnableKeyboard(true)
        wowFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                SMPPlayerSearch:Hide()
            end
        end)
    end

    frame:Hide()
end

function SMPPlayerSearch:Show(playerName)
    if not private.aceFrame then self:CreateFrame() end
    if not private.aceFrame then return end
    if playerName and playerName ~= "" then
        if private.editBox then private.editBox:SetText(playerName) end
        private:Search(playerName)
    end
    private.aceFrame:Show()
end

function SMPPlayerSearch:Hide()
    if private.copyFrame then private.copyFrame:Hide() end
    if private.aceFrame then private.aceFrame:Hide() end
end

function SMPPlayerSearch:Toggle()
    if private.aceFrame and private.aceFrame:IsShown() then self:Hide()
    else self:Show() end
end

function private:ClearScroll()
    if private.scroll then private.scroll:ReleaseChildren() end
end

function private:AddSeparator(text)
    if not private.scroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local h = AceGUI:Create("Heading")
    h:SetText(text)
    h:SetFullWidth(true)
    private.scroll:AddChild(h)
end

function private:AddLabel(text, fontObj)
    if not private.scroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local l = AceGUI:Create("Label")
    l:SetText(text)
    l:SetFullWidth(true)
    if fontObj then l:SetFontObject(fontObj) end
    private.scroll:AddChild(l)
end

function private:AddClickableRow(text, isSelected, onClick)
    if not private.scroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local row = AceGUI:Create("InteractiveLabel")
    local prefix = isSelected and "|cff1784d1>|r " or "   "
    row:SetText(prefix .. text)
    row:SetFullWidth(true)
    row:SetFontObject(isSelected and GameFontHighlight or GameFontNormal)
    row:SetCallback("OnClick", onClick)
    private.scroll:AddChild(row)
end

function private:AddDungeonRow(entry)
    if not private.scroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local durStr = formatDuration(entry.duration)
    local tmrStr = formatDuration(entry.timer)
    local statusIcon = entry.timed and "|cff00ff00+|r" or "|cffff2020-|r"
    local lvlText = keyColor(entry.level) .. "+" .. entry.level .. "|r"

    local row = AceGUI:Create("Label")
    row:SetText("    " .. entry.name .. "  " .. lvlText .. "  |cff888888" .. durStr .. " / " .. tmrStr .. "|r  " .. statusIcon)
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlightSmall)
    private.scroll:AddChild(row)
end

local CHECK_INTERVAL = 1
local REQUEST_INTERVAL = 3

function private:SelectPlayer(playerName)
    private.selectedPlayer = playerName
    private.lastRequestTime = 0

    if C_MythicPlus.RequestPlayerStat then
        C_MythicPlus.RequestPlayerStat(playerName)
        private.lastRequestTime = GetTime()
    end

    self:RenderResults(playerName)
    self:PollPlayerData(playerName, 1)
end

function private:PollPlayerData(playerName, attempt)
    if private.selectedPlayer ~= playerName then return end
    if attempt > MAX_RETRIES * 3 then return end

    C_Timer:After(CHECK_INTERVAL, function()
        if private.selectedPlayer ~= playerName then return end

        local dungeonData = buildPlayerDetail(playerName)
        if #dungeonData > 0 then
            self:RenderResults(playerName)
            return
        end

        local now = GetTime()
        if now - (private.lastRequestTime or 0) >= REQUEST_INTERVAL then
            if C_MythicPlus.RequestPlayerStat then
                C_MythicPlus.RequestPlayerStat(playerName)
                private.lastRequestTime = now
            end
        end

        self:PollPlayerData(playerName, attempt + 1)
    end)
end

function private:RenderResults(selectedName)
    self:ClearScroll()
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    if #private.searchResults == 0 then
        self:AddLabel("|cffff2020Игрок не найден в ладдере|r")
        return
    end

    if #private.searchResults > 1 then
        self:AddSeparator("Результаты (" .. #private.searchResults .. ")")
        for _, player in ipairs(private.searchResults) do
            local cc = classColor(player.classID)
            local rankStr = formatRank(player.rank)
            local scoreStr = player.score > 0 and ("  |cff888888" .. math.floor(player.score) .. "|r") or ""
            local text = "|c" .. cc .. player.name .. "|r  " .. rankStr .. scoreStr
            self:AddClickableRow(text, player.name == selectedName, function()
                private:SelectPlayer(player.name)
            end)
        end
    end

    if not selectedName then return end

    self:AddSeparator("Данные игрока")

    local found = false
    local profileURL = SMPLib:GetProfileURL(selectedName)
    for _, p in ipairs(private.searchResults) do
        if p.name == selectedName then
            found = true
            local cc = classColor(p.classID)
            local statText = "   |c" .. cc .. p.name .. "|r  " .. formatRank(p.rank) .. (p.score > 0 and ("  |cff1784d1" .. math.floor(p.score) .. "|r") or "")
            local row = AceGUI:Create("InteractiveLabel")
            row:SetText(statText .. "  |cff555555|||r  |cff1784d1Профиль|r")
            row:SetFullWidth(true)
            row:SetFontObject(GameFontHighlight)
            row:SetCallback("OnClick", function()
                private:ShowCopyDialog(profileURL)
            end)
            row:SetCallback("OnEnter", function(self)
                self.label:SetTextColor(0.3, 0.65, 1)
                GameTooltip:SetOwner(self.frame, "ANCHOR_CURSOR")
                GameTooltip:SetText(profileURL, 0.09, 0.52, 0.82)
                GameTooltip:AddLine("Кликните, чтобы скопировать", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            row:SetCallback("OnLeave", function(self)
                self.label:SetTextColor(1, 1, 1)
                GameTooltip:Hide()
            end)
            private.scroll:AddChild(row)
            break
        end
    end
    if not found then return end

    local dungeonData, bestLevel, bestDungeon, timed, total = buildPlayerDetail(selectedName)

    if #dungeonData == 0 then
        self:AddLabel("   |cff888888Данные по данжам загружаются...|r")
        return
    end

    if bestLevel > 0 then
        self:AddLabel("   |cff00ff00Лучший:|r " .. keyColor(bestLevel) .. "+" .. bestLevel .. "|r  " .. bestDungeon .. "        |cff00ff00Забеги:|r " .. timed .. "/" .. total)
    end

    self:AddSeparator("Данжи")
    for _, entry in ipairs(dungeonData) do
        self:AddDungeonRow(entry)
    end
end

function private:Search(playerName)
    if not playerName or playerName == "" then return end
    playerName = playerName:gsub("^%s+", ""):gsub("%s+$", "")

    private.pendingSearch = playerName
    private.selectedPlayer = nil
    private.searchResults = {}

    self:ClearScroll()
    self:AddLabel("|cff888888Поиск " .. playerName .. "...|r")

    if C_MythicPlus.RequestPlayerStat then
        C_MythicPlus.RequestPlayerStat(playerName)
    end

    if C_Ladder and C_Ladder.RequestSearch then
        pcall(function() C_Ladder.RequestSearch(MYTHIC_PLUS_BRACKET, playerName) end)
    end

    private:PollForResult(playerName, 1)
end

function private:PollForResult(playerName, attempt)
    if not private.pendingSearch or private.pendingSearch ~= playerName then return end
    if attempt > MAX_RETRIES then
        private.searchResults = getSearchResults()
        self:RenderResults(nil)
        private.pendingSearch = nil
        return
    end

    C_Timer:After(CHECK_INTERVAL, function()
        if not private.pendingSearch or private.pendingSearch ~= playerName then return end

        local results = getSearchResults()
        if #results > 0 then
            private.searchResults = results
            if #results == 1 then
                private:SelectPlayer(results[1].name)
            else
                self:RenderResults(nil)
            end
            private.pendingSearch = nil
            return
        end

        private:PollForResult(playerName, attempt + 1)
    end)
end

return SMPPlayerSearch
