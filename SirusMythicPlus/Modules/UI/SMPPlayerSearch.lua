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

local BRAND = { 0.09, 0.52, 0.82 }
local PURPLE = { 0.46, 0.33, 0.55 }
local PURPLE_LIGHT = { 0.69, 0.55, 0.82 }
local BG_DARK = { 0.055, 0.047, 0.067, 0.95 }
local BG_ROW = { 0.08, 0.07, 0.09, 0.9 }
local BG_ROW_HOVER = { 0.12, 0.10, 0.14, 0.95 }
local BG_ROW_SELECTED = { 0.10, 0.13, 0.18, 0.95 }
local BORDER_DARK = { 0.20, 0.17, 0.25, 0.6 }
local GREEN = { 0.33, 0.78, 0.47 }
local RED = { 0.85, 0.33, 0.33 }
local GRAY = { 0.47, 0.47, 0.47 }
local WHITE = { 1, 1, 1 }
local GOLD = { 0.90, 0.78, 0.0 }
local ORANGE = { 0.91, 0.60, 0.29 }
local PURPLE_KEY = { 0.64, 0.42, 0.91 }
local BLUE_KEY = { 0.0, 0.44, 0.87 }

local CLASS_COLORS = {
    [1] = { 0.78, 0.61, 0.43 }, [2] = { 0.96, 0.55, 0.73 }, [3] = { 0.67, 0.83, 0.45 },
    [4] = { 1.0, 0.96, 0.41 }, [5] = { 1.0, 1.0, 1.0 },    [6] = { 0.78, 0.61, 0.43 },
    [7] = { 0.0, 0.44, 0.87 }, [8] = { 0.41, 0.80, 0.94 }, [9] = { 0.58, 0.51, 0.79 },
    [11] = { 1.0, 0.49, 0.04 },
}

local function classColor(id) return CLASS_COLORS[id] or WHITE end

local function keyColorRGB(level)
    level = tonumber(level or 0) or 0
    if level >= 15 then return GOLD
    elseif level >= 10 then return PURPLE_KEY
    else return BLUE_KEY
    end
end

local function rankColorRGB(rank)
    if not rank then return GRAY end
    if rank <= 20 then return GOLD
    elseif rank <= 100 then return ORANGE
    elseif rank <= 1000 then return PURPLE_KEY
    else return GRAY
    end
end

local function scoreColorRGB(score)
    score = tonumber(score or 0) or 0
    local t = math.min(1, math.max(0, score / 2500))
    if t < 0.35 then
        return { BLUE_KEY[1] + (PURPLE_KEY[1] - BLUE_KEY[1]) * (t / 0.35),
                 BLUE_KEY[2] + (PURPLE_KEY[2] - BLUE_KEY[2]) * (t / 0.35),
                 BLUE_KEY[3] + (PURPLE_KEY[3] - BLUE_KEY[3]) * (t / 0.35) }
    elseif t < 0.65 then
        local lt = (t - 0.35) / 0.30
        return { PURPLE_KEY[1] + (ORANGE[1] - PURPLE_KEY[1]) * lt,
                 PURPLE_KEY[2] + (ORANGE[2] - PURPLE_KEY[2]) * lt,
                 PURPLE_KEY[3] + (ORANGE[3] - PURPLE_KEY[3]) * lt }
    else
        local lt = (t - 0.65) / 0.35
        return { ORANGE[1] + (GOLD[1] - ORANGE[1]) * lt,
                 ORANGE[2] + (GOLD[2] - ORANGE[2]) * lt,
                 ORANGE[3] + (GOLD[3] - ORANGE[3]) * lt }
    end
end

local function formatDuration(sec)
    if not sec or sec == 0 then return "-" end
    return math.floor(sec / 60) .. ":" .. string.format("%02d", sec % 60)
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
        f:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.97)
        f:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)

        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        label:SetPoint("TOPLEFT", 10, -8)
        label:SetText("Ссылка на профиль — Ctrl+C для копирования")
        label:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

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
        bg:SetVertexColor(0.08, 0.07, 0.10, 1)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
        end)

        private.copyFrame = f
        private.copyEditBox = eb
    end

    if private.aceFrame and private.aceFrame.frame then
        private.copyFrame:SetPoint("TOP", private.aceFrame.frame, "BOTTOM", 0, -4)
    end

    private.copyEditBox:SetText(url)
    private.copyFrame:Show()
    private.copyEditBox:SetFocus()
    private.copyEditBox:HighlightText()
end

local ROW_HEIGHT = 30
local DUNGEON_ROW_HEIGHT = 24

local function createPlayerRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints(row)
    bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], BG_ROW[4])
    row.bg = bg

    local indicator = row:CreateFontString(nil, "OVERLAY")
    indicator:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    indicator:SetPoint("LEFT", row, "LEFT", 6, 0)
    indicator:SetWidth(12)
    indicator:SetJustifyH("CENTER")
    row.indicator = indicator

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\ARIALN.TTF", 11, "")
    nameText:SetPoint("LEFT", indicator, "RIGHT", 4, 0)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local scoreText = row:CreateFontString(nil, "OVERLAY")
    scoreText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    scoreText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    scoreText:SetJustifyH("RIGHT")
    row.scoreText = scoreText

    local rankText = row:CreateFontString(nil, "OVERLAY")
    rankText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    rankText:SetPoint("RIGHT", scoreText, "LEFT", -10, 0)
    rankText:SetJustifyH("RIGHT")
    rankText:SetWidth(48)
    row.rankText = rankText

    nameText:SetPoint("RIGHT", rankText, "LEFT", -6, 0)

    row:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self.bg:SetVertexColor(BG_ROW_HOVER[1], BG_ROW_HOVER[2], BG_ROW_HOVER[3], BG_ROW_HOVER[4])
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self.bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], BG_ROW[4])
        end
    end)

    return row
end

local function createDungeonRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(DUNGEON_ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints(row)
    bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], 0.4)
    row.bg = bg

    local statusText = row:CreateFontString(nil, "OVERLAY")
    statusText:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    statusText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    statusText:SetJustifyH("RIGHT")
    statusText:SetWidth(14)
    row.statusText = statusText

    local timerText = row:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    timerText:SetPoint("RIGHT", statusText, "LEFT", -6, 0)
    timerText:SetJustifyH("RIGHT")
    timerText:SetWidth(90)
    row.timerText = timerText

    local levelText = row:CreateFontString(nil, "OVERLAY")
    levelText:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
    levelText:SetPoint("RIGHT", timerText, "LEFT", -8, 0)
    levelText:SetJustifyH("RIGHT")
    levelText:SetWidth(36)
    row.levelText = levelText

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
    nameText:SetPoint("RIGHT", levelText, "LEFT", -6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    return row
end

function SMPPlayerSearch:CreateFrame()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(string.format("|cff%02x%02x%02xSMP|r — Поиск игроков Mythic+",
        BRAND[1] * 255, BRAND[2] * 255, BRAND[3] * 255))
    frame:SetWidth(720)
    frame:SetHeight(430)
    frame:SetLayout("Fill")
    frame:EnableResize(false)

    local wowFrame = frame.frame
    if wowFrame then
        if wowFrame.SetBackdropBorderColor then
            wowFrame:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)
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
    private.playerRows = {}
    private.dungeonRows = {}

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

function private:ClearContainer(container)
    if container then container:ReleaseChildren() end
end

function private:AddAceLabel(container, text, fontObj)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local l = AceGUI:Create("Label")
    l:SetText(text)
    l:SetFullWidth(true)
    if fontObj then l:SetFontObject(fontObj) end
    container:AddChild(l)
end

function private:AddAceHeading(container, text)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end
    local h = AceGUI:Create("Heading")
    h:SetText(text)
    h:SetFullWidth(true)
    container:AddChild(h)
end

function private:AddCustomFrame(container, frame)
    local wrapper = AceGUI:Create("SimpleGroup")
    wrapper:SetFullWidth(true)
    wrapper:SetLayout("Fill")
    wrapper:SetHeight(frame:GetHeight())
    wrapper:AddChild({ frame = frame, type = "custom" })
    container:AddChild(wrapper)
    return wrapper
end

function private:CreatePlayerRowInContainer(container, player, isSelected, onClick)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local row = createPlayerRow(container.frame or container.content)

    local cc = classColor(player.classID)
    local rc = rankColorRGB(player.rank)
    local sc = scoreColorRGB(player.score)

    row.indicator:SetText(isSelected and ">" or "")
    row.indicator:SetTextColor(BRAND[1], BRAND[2], BRAND[3])

    row.nameText:SetText(player.name)
    row.nameText:SetTextColor(cc[1], cc[2], cc[3])

    if player.rank then
        row.rankText:SetText("#" .. player.rank)
        row.rankText:SetTextColor(rc[1], rc[2], rc[3])
    else
        row.rankText:SetText("")
    end

    if player.score > 0 then
        row.scoreText:SetText(math.floor(player.score))
        row.scoreText:SetTextColor(sc[1], sc[2], sc[3])
    else
        row.scoreText:SetText("")
    end

    row.isSelected = isSelected
    if isSelected then
        row.bg:SetVertexColor(BG_ROW_SELECTED[1], BG_ROW_SELECTED[2], BG_ROW_SELECTED[3], BG_ROW_SELECTED[4])
    end

    row:SetScript("OnClick", onClick)

    local wrapper = AceGUI:Create("SimpleGroup")
    wrapper:SetFullWidth(true)
    wrapper:SetLayout("Fill")
    wrapper:SetHeight(ROW_HEIGHT)
    container:AddChild(wrapper)

    wrapper.frame = row
    row:SetParent(wrapper.content or wrapper.frame)
    row:ClearAllPoints()
    row:SetAllPoints(wrapper.content or wrapper.frame)
    row:Show()

    return row
end

function private:CreateDungeonRowInContainer(container, entry)
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local row = createDungeonRow(container.frame or container.content)

    row.nameText:SetText(entry.name)
    row.nameText:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

    local kc = keyColorRGB(entry.level)
    row.levelText:SetText("+" .. entry.level)
    row.levelText:SetTextColor(kc[1], kc[2], kc[3])

    row.timerText:SetText(formatDuration(entry.duration) .. " / " .. formatDuration(entry.timer))
    row.timerText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

    if entry.timed then
        row.statusText:SetText("+")
        row.statusText:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    else
        row.statusText:SetText("-")
        row.statusText:SetTextColor(RED[1], RED[2], RED[3])
    end

    local wrapper = AceGUI:Create("SimpleGroup")
    wrapper:SetFullWidth(true)
    wrapper:SetLayout("Fill")
    wrapper:SetHeight(DUNGEON_ROW_HEIGHT)
    container:AddChild(wrapper)

    wrapper.frame = row
    row:SetParent(wrapper.content or wrapper.frame)
    row:ClearAllPoints()
    row:SetAllPoints(wrapper.content or wrapper.frame)
    row:Show()

    return row
end

function private:RenderPlayerList(selectedName)
    self:ClearContainer(private.leftScroll)
    if not private.leftScroll then return end

    if #private.searchResults == 0 then
        self:AddAceLabel(private.leftScroll, "|cff777777Нет результатов|r")
        return
    end

    self:AddAceLabel(private.leftScroll, string.format("|cff%02x%02x%02xРезультаты (%d)|r",
        PURPLE[1] * 255, PURPLE[2] * 255, PURPLE[3] * 255, #private.searchResults), GameFontNormalSmall)

    for _, player in ipairs(private.searchResults) do
        self:CreatePlayerRowInContainer(private.leftScroll, player, player.name == selectedName, function()
            private:SelectPlayer(player.name)
        end)
    end
end

function private:RenderPlayerDetails(selectedName)
    self:ClearContainer(private.rightScroll)
    if not private.rightScroll then return end
    local AceGUI = LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    if not selectedName then
        self:AddAceLabel(private.rightScroll, "|cff777777Выберите игрока из списка|r")
        return
    end

    local found = false
    local profileURL = SMPLib:GetProfileURL(selectedName)
    for _, p in ipairs(private.searchResults) do
        if p.name == selectedName then
            found = true
            local cc = classColor(p.classID)
            local rc = rankColorRGB(p.rank)
            local sc = scoreColorRGB(p.score)

            local header = AceGUI:Create("InteractiveLabel")
            local hText = string.format("|cff%02x%02x%02x%s|r  |cff%02x%02x%02x#%s|r  |cff%02x%02x%02x%s|r  |cff555555|||r  |cff%02x%02x%02xПрофиль|r",
                cc[1] * 255, cc[2] * 255, cc[3] * 255, p.name,
                rc[1] * 255, rc[2] * 255, rc[3] * 255, tostring(p.rank or ""),
                sc[1] * 255, sc[2] * 255, sc[3] * 255, math.floor(p.score),
                PURPLE_LIGHT[1] * 255, PURPLE_LIGHT[2] * 255, PURPLE_LIGHT[3] * 255)
            header:SetText(hText)
            header:SetFullWidth(true)
            header:SetFontObject(GameFontHighlight)
            header:SetCallback("OnClick", function()
                private:ShowCopyDialog(profileURL)
            end)
            header:SetCallback("OnEnter", function(self)
                self.label:SetTextColor(BRAND[1], BRAND[2], BRAND[3])
                GameTooltip:SetOwner(self.frame, "ANCHOR_CURSOR")
                GameTooltip:SetText(profileURL, PURPLE[1], PURPLE[2], PURPLE[3])
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
        self:AddAceHeading(private.rightScroll, "Данные игрока")
        self:AddAceLabel(private.rightScroll, "|cff777777Данные по данжам загружаются...|r")
        return
    end

    self:AddAceHeading(private.rightScroll, "Данные игрока")

    if bestLevel > 0 then
        local kc = keyColorRGB(bestLevel)
        local bestText = string.format("|cff%02x%02x%02xЛучший:|r |cff%02x%02x%02x+%d|r %s        |cff%02x%02x%02xЗабеги:|r %d/%d",
            GREEN[1] * 255, GREEN[2] * 255, GREEN[3] * 255,
            kc[1] * 255, kc[2] * 255, kc[3] * 255, bestLevel, bestDungeon,
            GREEN[1] * 255, GREEN[2] * 255, GREEN[3] * 255, timed, total)
        self:AddAceLabel(private.rightScroll, bestText)
    end

    self:AddAceHeading(private.rightScroll, "Данжи")

    for _, entry in ipairs(dungeonData) do
        self:CreateDungeonRowInContainer(private.rightScroll, entry)
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

    self:ClearContainer(private.leftScroll)
    self:ClearContainer(private.rightScroll)
    self:AddAceLabel(private.leftScroll, "|cff777777Поиск " .. playerName .. "...|r")

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
