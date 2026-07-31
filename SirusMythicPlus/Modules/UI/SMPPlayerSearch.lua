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

local DEFAULT_FONT_SIZE = 13

local function getSearchFontPath(sizeOffset, flags)
    local fontName = SMPConfig:GetProfileConfig("search.font")
    local font = SMPLib:FetchFont(fontName)
    local size = (SMPConfig:GetProfileConfig("search.fontSize") or DEFAULT_FONT_SIZE) + (sizeOffset or 0)
    local f = flags or SMPConfig:GetProfileConfig("search.fontFlags") or ""
    return font, size, f
end

local BRAND = { 0.09, 0.52, 0.82 }
local PURPLE = { 0.46, 0.33, 0.55 }
local PURPLE_LIGHT = { 0.69, 0.55, 0.82 }
local BG_DARK = { 0.055, 0.047, 0.067 }
local BG_PANEL = { 0.04, 0.035, 0.05 }
local BG_ROW = { 0.075, 0.065, 0.085 }
local BG_ROW_HOVER = { 0.11, 0.09, 0.13 }
local BG_ROW_SELECTED = { 0.09, 0.12, 0.17 }
local BORDER_PURPLE = { 0.46, 0.33, 0.55, 0.5 }
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
    else return BLUE_KEY end
end

local function rankColorRGB(rank)
    if not rank then return GRAY end
    if rank <= 20 then return GOLD
    elseif rank <= 100 then return ORANGE
    elseif rank <= 1000 then return PURPLE_KEY
    else return GRAY end
end

local function scoreColorRGB(score)
    score = tonumber(score or 0) or 0
    local t = math.min(1, math.max(0, score / 2500))
    if t < 0.35 then
        local lt = t / 0.35
        return { BLUE_KEY[1] + (PURPLE_KEY[1] - BLUE_KEY[1]) * lt,
                 BLUE_KEY[2] + (PURPLE_KEY[2] - BLUE_KEY[2]) * lt,
                 BLUE_KEY[3] + (PURPLE_KEY[3] - BLUE_KEY[3]) * lt }
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
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(BG_DARK[1], BG_DARK[2], BG_DARK[3], 0.97)
        f:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)

        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont(getSearchFontPath(-2))
        label:SetPoint("TOPLEFT", 10, -8)
        label:SetText("Ссылка на профиль — Ctrl+C для копирования")
        label:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(390, 20)
        eb:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        eb:SetFont(getSearchFontPath(-1))
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

    if private.mainFrame then
        private.copyFrame:SetPoint("TOP", private.mainFrame, "BOTTOM", 0, -4)
    end

    private.copyEditBox:SetText(url)
    private.copyFrame:Show()
    private.copyEditBox:SetFocus()
    private.copyEditBox:HighlightText()
end

local ROW_HEIGHT = 30
local DUNGEON_ROW_HEIGHT = 24
local SCROLL_INDENT = 4

local function createStyledBackdrop(frame, r, g, b, a, borderR, borderG, borderB, borderA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(r, g, b, a or 1)
    frame:SetBackdropBorderColor(borderR or 0, borderG or 0, borderB or 0, borderA or 0)
end

local function createPlayerRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints(row)
    bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], 0.9)
    row.bg = bg

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(getSearchFontPath(-1))
    nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local rankText = row:CreateFontString(nil, "OVERLAY")
    rankText:SetFont(getSearchFontPath(-2))
    rankText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    rankText:SetJustifyH("RIGHT")
    rankText:SetWidth(52)
    row.rankText = rankText

    local scoreText = row:CreateFontString(nil, "OVERLAY")
    scoreText:SetFont(getSearchFontPath(-2))
    scoreText:SetPoint("RIGHT", rankText, "LEFT", -4, 0)
    scoreText:SetJustifyH("RIGHT")
    scoreText:SetWidth(50)
    row.scoreText = scoreText

    nameText:SetPoint("RIGHT", scoreText, "LEFT", -6, 0)

    row:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self.bg:SetVertexColor(BG_ROW_HOVER[1], BG_ROW_HOVER[2], BG_ROW_HOVER[3], 0.95)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self.bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], 0.9)
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
    bg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], 0.35)
    row.bg = bg

    local statusText = row:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(getSearchFontPath(-1, "OUTLINE"))
    statusText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    statusText:SetJustifyH("RIGHT")
    statusText:SetWidth(14)
    row.statusText = statusText

    local timerText = row:CreateFontString(nil, "OVERLAY")
    timerText:SetFont(getSearchFontPath(-2))
    timerText:SetPoint("RIGHT", statusText, "LEFT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    timerText:SetWidth(90)
    row.timerText = timerText

    local levelText = row:CreateFontString(nil, "OVERLAY")
    levelText:SetFont(getSearchFontPath(-2, "OUTLINE"))
    levelText:SetPoint("RIGHT", timerText, "LEFT", -8, 0)
    levelText:SetJustifyH("RIGHT")
    levelText:SetWidth(36)
    row.levelText = levelText

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(getSearchFontPath(-2))
    nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
    nameText:SetPoint("RIGHT", levelText, "LEFT", -6, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    return row
end

local function clearScrollChild(scroll)
    local child = scroll:GetScrollChild()
    if child then
        child:Hide()
        child:SetParent(nil)
    end
    scroll:SetScrollChild(nil)
    scroll.rows = {}
end

local function initScrollContent(scroll)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(scroll:GetWidth() - SCROLL_INDENT)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll.rows = {}
    scroll.contentHeight = 0
    return child
end

local function addRowToScroll(scroll, row, height)
    local child = scroll:GetScrollChild()
    if not child then child = initScrollContent(scroll) end

    local y = scroll.contentHeight or 0
    row:SetParent(child)
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
    row:Show()

    scroll.contentHeight = y + height
    child:SetHeight(scroll.contentHeight)

    scroll.rows = scroll.rows or {}
    scroll.rows[#scroll.rows + 1] = row
end

function SMPPlayerSearch:CreateFrame()
    local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not AceGUI then return end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(string.format("|cff%02x%02x%02xSirusMythicPlus|r - Поиск игроков Mythic+",
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
        _G["SMPSearchFrame"] = wowFrame
        tinsert(UISpecialFrames, "SMPSearchFrame")
    end

    local content = frame.content
    if not content then return end

    local searchFrame = CreateFrame("Frame", nil, content)
    searchFrame:SetHeight(36)
    searchFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    searchFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -4)

    local editBoxBg = CreateFrame("Frame", nil, searchFrame)
    editBoxBg:SetHeight(26)
    editBoxBg:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 2, -4)
    editBoxBg:SetPoint("TOPRIGHT", searchFrame, "TOPRIGHT", -82, -4)
    createStyledBackdrop(editBoxBg, BG_PANEL[1], BG_PANEL[2], BG_PANEL[3], 1,
        PURPLE[1], PURPLE[2], PURPLE[3], 0.6)

    local editBox = CreateFrame("EditBox", nil, editBoxBg)
    editBox:SetHeight(26)
    editBox:SetPoint("TOPLEFT", editBoxBg, "TOPLEFT", 8, 0)
    editBox:SetPoint("TOPRIGHT", editBoxBg, "TOPRIGHT", -8, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFont(getSearchFontPath(0))
    editBox:SetTextColor(1, 1, 1)
    editBox:SetScript("OnEnterPressed", function(self) private:Search(self:GetText()) end)
    editBox:SetScript("OnEscapePressed", function() SMPPlayerSearch:Hide() end)
    editBox:SetScript("OnEditFocusGained", function(self)
        createStyledBackdrop(editBoxBg, BG_PANEL[1], BG_PANEL[2], BG_PANEL[3], 1,
            BRAND[1], BRAND[2], BRAND[3], 0.9)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        createStyledBackdrop(editBoxBg, BG_PANEL[1], BG_PANEL[2], BG_PANEL[3], 1,
            PURPLE[1], PURPLE[2], PURPLE[3], 0.6)
    end)

    local placeholder = editBoxBg:CreateFontString(nil, "OVERLAY")
    placeholder:SetFont(getSearchFontPath(-1))
    placeholder:SetPoint("LEFT", editBoxBg, "LEFT", 8, 0)
    placeholder:SetText("Введите имя игрока...")
    placeholder:SetTextColor(GRAY[1], GRAY[2], GRAY[3], 0.6)
    editBox.placeholder = placeholder
    editBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" and not self:HasFocus() then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
    end)

    local searchBtn = CreateFrame("Button", nil, searchFrame)
    searchBtn:SetSize(72, 26)
    searchBtn:SetPoint("TOPRIGHT", searchFrame, "TOPRIGHT", -2, -4)
    createStyledBackdrop(searchBtn, BRAND[1], BRAND[2], BRAND[3], 0.8,
        BRAND[1], BRAND[2], BRAND[3], 1)
    searchBtn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = searchBtn:GetHighlightTexture()
    hl:SetVertexColor(BRAND[1] + 0.15, BRAND[2] + 0.15, BRAND[3] + 0.15, 0.3)
    local btnText = searchBtn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(getSearchFontPath(0))
    btnText:SetPoint("CENTER", searchBtn, "CENTER", 0, 0)
    btnText:SetText("Найти")
    btnText:SetTextColor(1, 1, 1)
    searchBtn:SetScript("OnMouseDown", function(self)
        btnText:SetPoint("CENTER", self, "CENTER", 1, -1)
    end)
    searchBtn:SetScript("OnMouseUp", function(self)
        btnText:SetPoint("CENTER", self, "CENTER", 0, 0)
    end)
    searchBtn:SetScript("OnClick", function() private:Search(editBox:GetText()) end)

    local mainFrame = CreateFrame("Frame", nil, content)
    mainFrame:SetPoint("TOPLEFT", searchFrame, "BOTTOMLEFT", 0, -2)
    mainFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 4)

    local leftPanel = CreateFrame("Frame", nil, mainFrame)
    leftPanel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(240)
    createStyledBackdrop(leftPanel, BG_PANEL[1], BG_PANEL[2], BG_PANEL[3], 0.8,
        BORDER_PURPLE[1], BORDER_PURPLE[2], BORDER_PURPLE[3], BORDER_PURPLE[4])

    local leftLabel = leftPanel:CreateFontString(nil, "OVERLAY")
    leftLabel:SetFont(getSearchFontPath(-1))
    leftLabel:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -6)
    leftLabel:SetText("Результаты")
    leftLabel:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])

    local leftScroll = CreateFrame("ScrollFrame", "SMPSearchLeftScroll", leftPanel)
    leftScroll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 4, -22)
    leftScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -4, 4)
    leftScroll:EnableMouseWheel(true)
    leftScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = math.max(0, self:GetVerticalScrollRange())
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 30)))
    end)

    local rightPanel = CreateFrame("Frame", nil, mainFrame)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 4, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    createStyledBackdrop(rightPanel, BG_PANEL[1], BG_PANEL[2], BG_PANEL[3], 0.5,
        0, 0, 0, 0)

    local rightScroll = CreateFrame("ScrollFrame", "SMPSearchRightScroll", rightPanel)
    rightScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -4)
    rightScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -4, 4)
    rightScroll:EnableMouseWheel(true)
    rightScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = math.max(0, self:GetVerticalScrollRange())
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 30)))
    end)

    private.aceFrame = frame
    private.mainFrame = wowFrame
    private.editBox = editBox
    private.leftScroll = leftScroll
    private.rightScroll = rightScroll
    private.leftLabel = leftLabel

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

function private:RenderPlayerList(selectedName)
    clearScrollChild(private.leftScroll)

    if #private.searchResults == 0 then
        local child = initScrollContent(private.leftScroll)
        local msg = child:CreateFontString(nil, "OVERLAY")
        msg:SetFont(getSearchFontPath(-1))
        msg:SetPoint("TOPLEFT", child, "TOPLEFT", 8, 0)
        msg:SetText("Нет результатов")
        msg:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
        private.leftLabel:SetText("Результаты")
        return
    end

    private.leftLabel:SetText(string.format("Результаты (%d)", #private.searchResults))

    for _, player in ipairs(private.searchResults) do
        local row = createPlayerRow(nil)
        local cc = classColor(player.classID)
        local rc = rankColorRGB(player.rank)
        local sc = scoreColorRGB(player.score)
        local isSelected = player.name == selectedName

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
            row.bg:SetVertexColor(BG_ROW_SELECTED[1], BG_ROW_SELECTED[2], BG_ROW_SELECTED[3], 0.95)
        end

        local playerName = player.name
        row:SetScript("OnClick", function() private:SelectPlayer(playerName) end)

        addRowToScroll(private.leftScroll, row, ROW_HEIGHT)
    end
end

function private:RenderPlayerDetails(selectedName)
    clearScrollChild(private.rightScroll)

    if not selectedName then
        local child = initScrollContent(private.rightScroll)
        local msg = child:CreateFontString(nil, "OVERLAY")
        msg:SetFont(getSearchFontPath(-1))
        msg:SetPoint("TOPLEFT", child, "TOPLEFT", 8, 0)
        msg:SetText("Выберите игрока из списка")
        msg:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
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

            local header = CreateFrame("Button", nil, nil)
            header:SetHeight(26)

            local hBg = header:CreateTexture(nil, "BACKGROUND")
            hBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            hBg:SetAllPoints(header)
            hBg:SetVertexColor(BG_ROW[1], BG_ROW[2], BG_ROW[3], 0.6)

            local hName = header:CreateFontString(nil, "OVERLAY")
            hName:SetFont(getSearchFontPath(0))
            hName:SetPoint("LEFT", header, "LEFT", 8, 0)
            hName:SetText(p.name)
            hName:SetTextColor(cc[1], cc[2], cc[3])

            local hScore = header:CreateFontString(nil, "OVERLAY")
            hScore:SetFont(getSearchFontPath(-1))
            hScore:SetPoint("LEFT", hName, "RIGHT", 8, 0)
            hScore:SetText(p.score > 0 and ("Счет: " .. math.floor(p.score)) or "")
            hScore:SetTextColor(sc[1], sc[2], sc[3])

            local hRank = header:CreateFontString(nil, "OVERLAY")
            hRank:SetFont(getSearchFontPath(-1))
            hRank:SetPoint("LEFT", hScore, "RIGHT", 8, 0)
            hRank:SetText(p.rank and ("Место в ладдере: " .. p.rank) or "")
            hRank:SetTextColor(rc[1], rc[2], rc[3])

            local hSep = header:CreateFontString(nil, "OVERLAY")
            hSep:SetFont(getSearchFontPath(-1))
            hSep:SetPoint("LEFT", hRank, "RIGHT", 8, 0)
            hSep:SetText("|")
            hSep:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

            local hLink = header:CreateFontString(nil, "OVERLAY")
            hLink:SetFont(getSearchFontPath(-1))
            hLink:SetPoint("LEFT", hSep, "RIGHT", 8, 0)
            hLink:SetText("Профиль")
            hLink:SetTextColor(PURPLE_LIGHT[1], PURPLE_LIGHT[2], PURPLE_LIGHT[3])

            header:SetScript("OnEnter", function()
                hLink:SetTextColor(BRAND[1], BRAND[2], BRAND[3])
                GameTooltip:SetOwner(header, "ANCHOR_CURSOR")
                GameTooltip:SetText(profileURL, PURPLE[1], PURPLE[2], PURPLE[3])
                GameTooltip:AddLine("Кликните, чтобы скопировать", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            header:SetScript("OnLeave", function()
                hLink:SetTextColor(PURPLE_LIGHT[1], PURPLE_LIGHT[2], PURPLE_LIGHT[3])
                GameTooltip:Hide()
            end)
            header:SetScript("OnClick", function()
                private:ShowCopyDialog(profileURL)
            end)

            addRowToScroll(private.rightScroll, header, 26)
            break
        end
    end
    if not found then return end

    local dungeonData, bestLevel, bestDungeon, timed, total = buildPlayerDetail(selectedName)

    if #dungeonData == 0 then
        local spacer = CreateFrame("Frame", nil, nil)
        spacer:SetHeight(8)
        addRowToScroll(private.rightScroll, spacer, 8)

        local msg = CreateFrame("Frame", nil, nil)
        msg:SetHeight(16)
        local msgText = msg:CreateFontString(nil, "OVERLAY")
        msgText:SetFont(getSearchFontPath(-1))
        msgText:SetPoint("LEFT", msg, "LEFT", 8, 0)
        msgText:SetText("Данные по данжам загружаются...")
        msgText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
        addRowToScroll(private.rightScroll, msg, 16)
        return
    end

    local sectionH = 10
    local spacer = CreateFrame("Frame", nil, nil)
    spacer:SetHeight(sectionH)
    addRowToScroll(private.rightScroll, spacer, sectionH)

    addRowToScroll(private.rightScroll, (function()
        local h = CreateFrame("Frame", nil, nil)
        h:SetHeight(22)
        local txt = h:CreateFontString(nil, "OVERLAY")
        txt:SetFont(getSearchFontPath(1, "OUTLINE"))
        txt:SetPoint("CENTER", h, "CENTER", 0, 0)
        txt:SetText(" Данные игрока ")
        txt:SetTextColor(1.0, 0.82, 0.0)
        local lineL = h:CreateTexture(nil, "BACKGROUND")
        lineL:SetHeight(1)
        lineL:SetPoint("LEFT", h, "LEFT", 8, 0)
        lineL:SetPoint("RIGHT", txt, "LEFT", -6, 0)
        lineL:SetTexture("Interface\\Buttons\\WHITE8X8")
        lineL:SetVertexColor(1.0, 0.82, 0.0, 0.5)
        local lineR = h:CreateTexture(nil, "BACKGROUND")
        lineR:SetHeight(1)
        lineR:SetPoint("LEFT", txt, "RIGHT", 6, 0)
        lineR:SetPoint("RIGHT", h, "RIGHT", -8, 0)
        lineR:SetTexture("Interface\\Buttons\\WHITE8X8")
        lineR:SetVertexColor(1.0, 0.82, 0.0, 0.5)
        return h
    end)(), 22)

    if bestLevel > 0 then
        local bestRow = CreateFrame("Frame", nil, nil)
        bestRow:SetHeight(18)

        local kc = keyColorRGB(bestLevel)

        local bLabel = bestRow:CreateFontString(nil, "OVERLAY")
        bLabel:SetFont(getSearchFontPath(-1))
        bLabel:SetPoint("LEFT", bestRow, "LEFT", 8, 0)
        bLabel:SetText("Лучший:")
        bLabel:SetTextColor(GREEN[1], GREEN[2], GREEN[3])

        local bKey = bestRow:CreateFontString(nil, "OVERLAY")
        bKey:SetFont(getSearchFontPath(-1, "OUTLINE"))
        bKey:SetPoint("LEFT", bLabel, "RIGHT", 4, 0)
        bKey:SetText("+" .. bestLevel)
        bKey:SetTextColor(kc[1], kc[2], kc[3])

        local bDungeon = bestRow:CreateFontString(nil, "OVERLAY")
        bDungeon:SetFont(getSearchFontPath(-1))
        bDungeon:SetPoint("LEFT", bKey, "RIGHT", 4, 0)
        bDungeon:SetText(bestDungeon)
        bDungeon:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

        local bRuns = bestRow:CreateFontString(nil, "OVERLAY")
        bRuns:SetFont(getSearchFontPath(-1))
        bRuns:SetPoint("RIGHT", bestRow, "RIGHT", -8, 0)
        bRuns:SetText(string.format("Забеги: %d/%d", timed, total))
        bRuns:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

        local bRunsLabel = bestRow:CreateFontString(nil, "OVERLAY")
        bRunsLabel:SetFont(getSearchFontPath(-1))
        bRunsLabel:SetPoint("RIGHT", bRuns, "LEFT", -4, 0)
        bRunsLabel:SetText("Забеги:")
        bRunsLabel:SetTextColor(GREEN[1], GREEN[2], GREEN[3])

        addRowToScroll(private.rightScroll, bestRow, 18)
    end

    local spacer2 = CreateFrame("Frame", nil, nil)
    spacer2:SetHeight(sectionH)
    addRowToScroll(private.rightScroll, spacer2, sectionH)

    addRowToScroll(private.rightScroll, (function()
        local h = CreateFrame("Frame", nil, nil)
        h:SetHeight(22)
        local txt = h:CreateFontString(nil, "OVERLAY")
        txt:SetFont(getSearchFontPath(1, "OUTLINE"))
        txt:SetPoint("CENTER", h, "CENTER", 0, 0)
        txt:SetText(" Данжи ")
        txt:SetTextColor(1.0, 0.82, 0.0)
        local lineL = h:CreateTexture(nil, "BACKGROUND")
        lineL:SetHeight(1)
        lineL:SetPoint("LEFT", h, "LEFT", 8, 0)
        lineL:SetPoint("RIGHT", txt, "LEFT", -6, 0)
        lineL:SetTexture("Interface\\Buttons\\WHITE8X8")
        lineL:SetVertexColor(1.0, 0.82, 0.0, 0.5)
        local lineR = h:CreateTexture(nil, "BACKGROUND")
        lineR:SetHeight(1)
        lineR:SetPoint("LEFT", txt, "RIGHT", 6, 0)
        lineR:SetPoint("RIGHT", h, "RIGHT", -8, 0)
        lineR:SetTexture("Interface\\Buttons\\WHITE8X8")
        lineR:SetVertexColor(1.0, 0.82, 0.0, 0.5)
        return h
    end)(), 22)

    for _, entry in ipairs(dungeonData) do
        local row = createDungeonRow(nil)
        local kc = keyColorRGB(entry.level)

        row.nameText:SetText(entry.name)
        row.nameText:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

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

        addRowToScroll(private.rightScroll, row, DUNGEON_ROW_HEIGHT)
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

function private:Search(playerName)
    if not playerName or playerName == "" then return end
    playerName = playerName:gsub("^%s+", ""):gsub("%s+$", "")

    private.pendingSearch = playerName
    private.selectedPlayer = nil
    private.searchResults = {}

    clearScrollChild(private.leftScroll)
    clearScrollChild(private.rightScroll)

    local child = initScrollContent(private.leftScroll)
    local msg = child:CreateFontString(nil, "OVERLAY")
    msg:SetFont(getSearchFontPath(-1))
    msg:SetPoint("TOPLEFT", child, "TOPLEFT", 8, 0)
    msg:SetText("Поиск " .. playerName .. "...")
    msg:SetTextColor(GRAY[1], GRAY[2], GRAY[3])

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

function private:RenderResults(selectedName)
    self:RenderPlayerList(selectedName)
    self:RenderPlayerDetails(selectedName)
end

return SMPPlayerSearch
