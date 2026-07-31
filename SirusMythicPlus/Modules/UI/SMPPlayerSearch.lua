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

local PURPLE_BORDER = { 0.46, 0.33, 0.55, 1 }
local PURPLE_ACCENT = "|cff76558d"
local PURPLE_TEXT = "|cffb18bd0"
local BRAND = "|cff1784d1"
local GREEN = "|cff54c878"
local MUTED = "|cff777777"

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
        local rank, name, _, classID, _, _, _, score = C_Ladder.GetSearchResultPlayerInfo(MYTHIC_PLUS_BRACKET, i)
        if name then
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
        f:SetBackdropColor(0.06, 0.05, 0.07, 0.97)
        f:SetBackdropBorderColor(PURPLE_BORDER[1], PURPLE_BORDER[2], PURPLE_BORDER[3], 1)

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
        bg:SetVertexColor(0.1, 0.08, 0.12, 1)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
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

local function addSectionTitle(container, text)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local h = AceGUI:Create("Heading")
    h:SetText(text)
    h:SetFullWidth(true)
    container:AddChild(h)
end

local function addDetailLabel(container, text, fontObj)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local l = AceGUI:Create("Label")
    l:SetText(text)
    l:SetFullWidth(true)
    if fontObj then l:SetFontObject(fontObj) end
    container:AddChild(l)
end

local function addDungeonRow(container, entry)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local durStr = formatDuration(entry.duration)
    local tmrStr = formatDuration(entry.timer)
    local statusIcon = entry.timed and (GREEN .. "+|r") or ("|cffff2020-|r")
    local lvlText = keyColor(entry.level) .. "+" .. entry.level .. "|r"

    local row = AceGUI:Create("Label")
    row:SetText(entry.name .. "  " .. lvlText .. "  " .. MUTED .. durStr .. " / " .. tmrStr .. "|r  " .. statusIcon)
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlightSmall)
    container:AddChild(row)
end

function SMPPlayerSearch:CreateFrame()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(BRAND .. "SMP|r — Поиск игроков Mythic+")
    frame:SetWidth(720)
    frame:SetHeight(430)
    frame:SetLayout("Fill")
    frame:EnableResize(false)

    local wowFrame = frame.frame
    if wowFrame then
        if wowFrame.SetBackdropBorderColor then
            wowFrame:SetBackdropBorderColor(PURPLE_BORDER[1], PURPLE_BORDER[2], PURPLE_BORDER[3], 1)
        end
        wowFrame:EnableKeyboard(true)
        wowFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then SMPPlayerSearch:Hide() end
        end)
    end

    local root = AceGUI:Create("SimpleGroup")
    root:SetFullWidth(true)
    root:SetFullHeight(true)
    root:SetLayout("Flow")
    frame:AddChild(root)

    local searchRow = AceGUI:Create("SimpleGroup")
    searchRow:SetFullWidth(true)
    searchRow:SetLayout("Flow")
    root:AddChild(searchRow)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel(nil)
    editBox:SetRelativeWidth(0.78)
    editBox:DisableButton(true)
    editBox:SetCallback("OnEnterPressed", function(_, _, text) private:Search(text) end)
    if editBox.editbox then
        editBox.editbox:SetScript("OnEnterPressed", function(self) private:Search(self:GetText()) end)
    end
    searchRow:AddChild(editBox)

    local searchBtn = AceGUI:Create("Button")
    searchBtn:SetText("Найти")
    searchBtn:SetRelativeWidth(0.20)
    searchBtn:SetCallback("OnClick", function() private:Search(editBox:GetText()) end)
    searchRow:AddChild(searchBtn)

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("Flow")
    root:AddChild(mainGroup)

    local leftPanel = AceGUI:Create("SimpleGroup")
    leftPanel:SetRelativeWidth(0.35)
    leftPanel:SetFullHeight(true)
    leftPanel:SetLayout("Fill")
    mainGroup:AddChild(leftPanel)

    local leftScroll = AceGUI:Create("ScrollFrame")
    leftScroll:SetLayout("List")
    leftScroll:SetFullWidth(true)
    leftScroll:SetFullHeight(true)
    leftPanel:AddChild(leftScroll)

    local rightPanel = AceGUI:Create("SimpleGroup")
    rightPanel:SetRelativeWidth(0.64)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("Fill")
    mainGroup:AddChild(rightPanel)

    local rightScroll = AceGUI:Create("ScrollFrame")
    rightScroll:SetLayout("List")
    rightScroll:SetFullWidth(true)
    rightScroll:SetFullHeight(true)
    rightPanel:AddChild(rightScroll)

    private.aceFrame = frame
    private.editBox = editBox
    private.leftScroll = leftScroll
    private.rightScroll = rightScroll

    frame:SetCallback("OnClose", function()
        if private.copyFrame then private.copyFrame:Hide() end
    end)

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

function private:ClearLeft()
    if private.leftScroll then private.leftScroll:ReleaseChildren() end
end

function private:ClearRight()
    if private.rightScroll then private.rightScroll:ReleaseChildren() end
end

function private:RenderPlayerList(selectedName)
    self:ClearLeft()
    if not private.leftScroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    if #private.searchResults == 0 then
        addDetailLabel(private.leftScroll, MUTED .. "Нет результатов|r")
        return
    end

    addDetailLabel(private.leftScroll, PURPLE_ACCENT .. "Результаты (" .. #private.searchResults .. ")|r", GameFontNormalSmall)

    for _, player in ipairs(private.searchResults) do
        local cc = classColor(player.classID)
        local isSelected = player.name == selectedName
        local indicator = isSelected and (BRAND .. ">|r") or "  "
        local nameText = "|c" .. cc .. player.name .. "|r"
        local rankStr = formatRank(player.rank)
        local scoreStr = player.score > 0 and (MUTED .. math.floor(player.score) .. "|r") or ""

        local row = AceGUI:Create("InteractiveLabel")
        row:SetText(indicator .. " " .. nameText .. "  " .. rankStr .. "  " .. scoreStr)
        row:SetFullWidth(true)
        row:SetFontObject(isSelected and GameFontHighlight or GameFontNormal)
        row:SetCallback("OnClick", function()
            private:SelectPlayer(player.name)
        end)
        private.leftScroll:AddChild(row)
    end
end

function private:RenderPlayerDetails(selectedName)
    self:ClearRight()
    if not private.rightScroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    if not selectedName then
        addDetailLabel(private.rightScroll, MUTED .. "Выберите игрока из списка|r")
        return
    end

    local found = false
    local profileURL = SMPLib:GetProfileURL(selectedName)
    for _, p in ipairs(private.searchResults) do
        if p.name == selectedName then
            found = true
            local cc = classColor(p.classID)
            local rankStr = formatRank(p.rank)
            local scoreStr = p.score > 0 and (BRAND .. math.floor(p.score) .. "|r") or ""

            local header = AceGUI:Create("InteractiveLabel")
            header:SetText("|c" .. cc .. p.name .. "|r  " .. rankStr .. "  " .. scoreStr .. "  " .. MUTED .. "|  |r" .. PURPLE_TEXT .. "Профиль|r")
            header:SetFullWidth(true)
            header:SetFontObject(GameFontHighlight)
            header:SetCallback("OnClick", function()
                private:ShowCopyDialog(profileURL)
            end)
            header:SetCallback("OnEnter", function(self)
                self.label:SetTextColor(0.3, 0.65, 1)
                GameTooltip:SetOwner(self.frame, "ANCHOR_CURSOR")
                GameTooltip:SetText(profileURL, 0.46, 0.33, 0.55)
                GameTooltip:AddLine("Кликните, чтобы скопировать", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            header:SetCallback("OnLeave", function(self)
                self.label:SetTextColor(1, 1, 1)
                GameTooltip:Hide()
            end)
            private.rightScroll:AddChild(header)
            break
        end
    end
    if not found then return end

    local dungeonData, bestLevel, bestDungeon, timed, total = buildPlayerDetail(selectedName)

    if #dungeonData == 0 then
        addSectionTitle(private.rightScroll, "Данные игрока")
        addDetailLabel(private.rightScroll, MUTED .. "Данные по данжам загружаются...|r")
        return
    end

    addSectionTitle(private.rightScroll, "Данные игрока")

    if bestLevel > 0 then
        local bestText = GREEN .. "Лучший:|r " .. keyColor(bestLevel) .. "+" .. bestLevel .. "|r " .. bestDungeon
        local runsText = GREEN .. "Забеги:|r " .. timed .. "/" .. total
        addDetailLabel(private.rightScroll, bestText .. "        " .. runsText)
    end

    addSectionTitle(private.rightScroll, "Данжи")

    for _, entry in ipairs(dungeonData) do
        addDungeonRow(private.rightScroll, entry)
    end
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

    self:RenderPlayerList(playerName)
    self:RenderPlayerDetails(playerName)
    self:PollPlayerData(playerName, 1)
end

function private:PollPlayerData(playerName, attempt)
    if private.selectedPlayer ~= playerName then return end
    if attempt > MAX_RETRIES * 3 then return end

    C_Timer:After(CHECK_INTERVAL, function()
        if private.selectedPlayer ~= playerName then return end

        local dungeonData = buildPlayerDetail(playerName)
        if #dungeonData > 0 then
            self:RenderPlayerDetails(playerName)
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
    self:RenderPlayerList(selectedName)
    self:RenderPlayerDetails(selectedName)
end

function private:Search(playerName)
    if not playerName or playerName == "" then return end
    playerName = playerName:gsub("^%s+", ""):gsub("%s+$", "")

    private.pendingSearch = playerName
    private.selectedPlayer = nil
    private.searchResults = {}

    self:ClearLeft()
    self:ClearRight()
    addDetailLabel(private.leftScroll, MUTED .. "Поиск " .. playerName .. "...|r")

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
