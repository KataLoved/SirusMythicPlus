---@class SMPDebug
local SMPDebug = SMPLoader:CreateModule("SMPDebug")
local private = SMPDebug.private

private.enabled = false
private.entries = {}
private.MAX_ENTRIES = 500
private.frame = nil
private.scrollChild = nil
private.linePool = {}
private.visibleLines = 0
private.LINE_HEIGHT = 14
private.VIEWPORT_LINES = 30

local CATEGORY_COLORS = {
    WOW_EVENT   = "FF00BFFF",
    BUS_FIRE    = "FF98FB98",
    STATE       = "FFFFD700",
    OVERLAY     = "FFFF69B4",
    POLL        = "FFFF8C00",
    REQUEST     = "FF9370DB",
    ERROR       = "FFFF4444",
    SYSTEM      = "FFCCCCCC",
}

local function timestamp()
    return date("%H:%M:%S") .. format(".%03d", (GetTime() % 1) * 1000)
end

function SMPDebug:Log(category, message)
    if not private.enabled then return end

    local color = CATEGORY_COLORS[category] or "FFCCCCCC"
    local entry = {
        time = timestamp(),
        category = category,
        color = color,
        message = message,
    }

    local entries = private.entries
    entries[#entries + 1] = entry
    if #entries > private.MAX_ENTRIES then
        table.remove(entries, 1)
    end

    if private.frame and private.frame:IsShown() then
        self:RefreshView()
    end
end

function SMPDebug:Toggle()
    private.enabled = not private.enabled
    if private.enabled then
        SMP:Print("|cff00ff00[DEBUG]|r Логирование ВКЛЮЧЕНО")
        self:Log("SYSTEM", "Debug logging enabled")
    else
        SMP:Print("|cffff0000[DEBUG]|r Логирование ВЫКЛЮЧЕНО")
    end
end

function SMPDebug:IsEnabled()
    return private.enabled
end

function SMPDebug:Clear()
    wipe(private.entries)
    if private.frame and private.frame:IsShown() then
        self:RefreshView()
    end
end

function SMPDebug:CreateLogWindow()
    if private.frame then return end

    local f = CreateFrame("Frame", "SMPDebugFrame", UIParent)
    f:SetSize(520, 440)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    f:Hide()

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
    end)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff00bfffSMP Debug Log|r")
    title:SetTextColor(0, 0.75, 1)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 18)
    clearBtn:SetPoint("TOPRIGHT", closeBtn, "BOTTOMLEFT", -4, 2)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        SMPDebug:Clear()
    end)

    local scroll = CreateFrame("ScrollFrame", "SMPDebugScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -30)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local viewport = CreateFrame("Frame", nil, f)
    viewport:SetPoint("TOPLEFT", 8, -30)
    viewport:SetPoint("BOTTOMRIGHT", -28, 8)
    viewport:SetClipsChildren(true)

    private.frame = f
    private.scroll = scroll
    private.viewport = viewport

    scroll:SetScript("OnVerticalScroll", function(_, offset)
        FauxScrollFrame_OnVerticalScroll(scroll, offset, private.LINE_HEIGHT, function()
            SMPDebug:RefreshView()
        end)
    end)

    for i = 1, private.VIEWPORT_LINES + 2 do
        local line = viewport:CreateFontString(nil, "OVERLAY")
        line:SetFont("Fonts\\ARIALN.TTF", 11, "")
        line:SetJustifyH("LEFT")
        line:SetNonSpaceWrap(false)
        line:SetWordWrap(false)
        line:SetHeight(private.LINE_HEIGHT)
        private.linePool[i] = line
    end
end

function SMPDebug:RefreshView()
    if not private.frame or not private.frame:IsShown() then return end

    local entries = private.entries
    local total = #entries
    local viewLines = private.VIEWPORT_LINES

    FauxScrollFrame_Update(private.scroll, total, viewLines, private.LINE_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(private.scroll)

    for i = 1, viewLines + 2 do
        local line = private.linePool[i]
        local idx = offset + i
        if idx <= total then
            local e = entries[idx]
            line:SetText("|c" .. e.color .. e.time .. " [" .. e.category .. "]|r " .. e.message)
            line:SetPoint("TOPLEFT", private.viewport, "TOPLEFT", 4, -(i - 1) * private.LINE_HEIGHT)
            line:Show()
        else
            line:Hide()
        end
    end
end

function SMPDebug:Show()
    if not private.frame then
        self:CreateLogWindow()
    end
    private.frame:Show()
    self:RefreshView()
end

function SMPDebug:Hide()
    if private.frame then
        private.frame:Hide()
    end
end

function SMPDebug:IsShown()
    return private.frame and private.frame:IsShown()
end

function SMPDebug:ToggleWindow()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function SMPDebug:DumpToChat(count)
    count = count or 20
    local entries = private.entries
    local start = math.max(1, #entries - count + 1)
    SMP:Print("|cff00bfff[DEBUG DUMP]|r Последние " .. math.min(count, #entries) .. " записей:")
    for i = start, #entries do
        local e = entries[i]
        SMP:Print("  |c" .. e.color .. e.time .. " [" .. e.category .. "]|r " .. e.message)
    end
end

function SMPDebug:HookMessageBus(bus)
    local originalFire = bus.Fire
    bus.Fire = function(self, eventName, ...)
        SMPDebug:Log("BUS_FIRE", eventName)
        return originalFire(self, eventName, ...)
    end
end
