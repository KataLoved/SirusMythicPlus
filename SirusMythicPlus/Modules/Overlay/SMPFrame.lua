---@class SMPFrame
local SMPFrame = SMPLoader:CreateModule("SMPFrame")
local private = SMPFrame.private

---@type SMPState
local SMPState = SMPLoader:ImportModule("SMPState")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

---@type SMPForcesData
local SMPForcesData = SMPLoader:ImportModule("SMPForcesData")

local LCG = LibStub("LibCustomGlow-1.0-ElvUI", true)
private.glowActive = false
private.glowType = nil -- combat/complete

local MAX_OBJECTIVES = 10
local format = string.format
local floor = math.floor
local math_min = math.min
local math_max = math.max
local math_abs = math.abs

private.frames = {}
private.isUnlocked = false

local function hexToRGB(hex)
    if not hex or hex == "" then return 1, 1, 1, 1 end
    hex = hex:gsub("^FF", "")
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    local a = hex:len() >= 8 and tonumber(hex:sub(7, 8), 16) or 255
    return r / 255, g / 255, b / 255, a / 255
end

local function formatTime(time)
    local timeMin = floor(time / 60)
    local timeSec = floor(time - timeMin * 60)
    return format("%d:%02d", timeMin, timeSec)
end

local function colorText(text, hex)
    return "|c" .. hex .. text .. "|r"
end

local function clamp(value, minVal, maxVal)
    return math_min(maxVal, math_max(minVal, value))
end

local function getConfig(path)
    return SMPConfig:GetProfileConfig(path)
end

local function getFont(path)
    local fontName = getConfig(path) or "Friz Quadrata TT"
    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
        if ok and lsm then
            local fontPath = lsm:Fetch("font", fontName)
            if fontPath then return fontPath end
        end
    end
    return fontName
end

local DEFAULT_STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local ELVUI_STATUSBAR_TEXTURE = "Interface\\Addons\\ElvUI\\Media\\Textures\\NormTex.tga"
local statusBarTextureCache = nil
local statusBarTextureResolved = false

local function resolveStatusBarTexture()
    if statusBarTextureResolved then
        return statusBarTextureCache or DEFAULT_STATUSBAR_TEXTURE
    end
    statusBarTextureResolved = true

    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
        if ok and lsm then
            for _, key in ipairs({ "ElvUI Norm", "ElvUI NormTex", "NormTex" }) do
                if lsm:IsValid("statusbar", key) then
                    local path = lsm:Fetch("statusbar", key, true)
                    if path then
                        statusBarTextureCache = path
                        return statusBarTextureCache
                    end
                end
            end
        end
    end

    if IsAddOnLoaded("ElvUI") then
        statusBarTextureCache = ELVUI_STATUSBAR_TEXTURE
        return statusBarTextureCache
    end

    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
        if ok and lsm then
            for _, key in ipairs({ "Melli", "melli 6px", "Melli 6px" }) do
                if lsm:IsValid("statusbar", key) then
                    local path = lsm:Fetch("statusbar", key, true)
                    if path then
                        statusBarTextureCache = path
                        return statusBarTextureCache
                    end
                end
            end
        end
    end

    statusBarTextureCache = DEFAULT_STATUSBAR_TEXTURE
    return statusBarTextureCache
end

local function getStatusBarTexture(path)
    local texName = getConfig(path) or "Solid"
    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
        if ok and lsm then
            local texPath = lsm:Fetch("statusbar", texName)
            if texPath then return texPath end
        end
    end
    return resolveStatusBarTexture()
end

local function createFontString(parent)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetNonSpaceWrap(false)
    return fs
end

local function createStatusBar(parent, name)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

function private:CreateFrames()
    local f = self.frames

    f.root = CreateFrame("Frame", "SMPFrameRoot", UIParent)
    f.root:SetSize(300, 200)
    f.root:SetPoint("CENTER", 0, 0)

    f.deathsText = createFontString(f.root)
    f.timerText = createFontString(f.root)
    f.timerSplitText = createFontString(f.root)
    f.keyText = createFontString(f.root)
    f.keyDetailsText = createFontString(f.root)

    f.bars = CreateFrame("Frame", nil, f.root)

    f.bar1 = createStatusBar(f.bars)
    f.bar1.text = createFontString(f.bar1)

    f.bar2 = createStatusBar(f.bars)
    f.bar2.text = createFontString(f.bar2)

    f.bar3 = createStatusBar(f.bars)
    f.bar3.text = createFontString(f.bar3)

    f.forces = createStatusBar(f.root)
    f.forcesOverlay = createStatusBar(f.root)
    f.forces.text = createFontString(f.forces)

    f.objectiveTexts = {}
    for i = 1, MAX_OBJECTIVES do
        f.objectiveTexts[i] = createFontString(f.root)
    end

    f.bg = f.root:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.bg:SetVertexColor(0, 0, 0, 0)

    self:SetupDrag()
end

function private:SetupDrag()
    local f = self.frames

    f.root:SetScript("OnMouseDown", function(frame, button)
        if private.isUnlocked and button == "LeftButton" and not frame.isMoving then
            frame:StartMoving()
            frame.isMoving = true
        end
    end)

    f.root:SetScript("OnMouseUp", function(frame, button)
        if button == "LeftButton" and frame.isMoving then
            frame:StopMovingOrSizing()
            frame.isMoving = false
            local _, _, _, x, y = frame:GetPoint(1)
            SMPConfig:UpdateProfileConfig("overlay.point", select(1, frame:GetPoint(1)))
            SMPConfig:UpdateProfileConfig("overlay.x", x)
            SMPConfig:UpdateProfileConfig("overlay.y", y)
        end
    end)

    f.root:SetScript("OnHide", function(frame)
        if frame.isMoving then
            frame:StopMovingOrSizing()
            frame.isMoving = false
        end
    end)
end

function SMPFrame:RenderLayout()
    local f = private.frames
    if not f.root then return end

    local cfg = SMPConfig.db.profile.overlay
    local pad = cfg.framePadding or 8
    local vOff = cfg.verticalOffset or 4
    local objOff = cfg.objectivesOffset or 2
    local barPad = cfg.barPadding or 4
    local barW = cfg.barWidth or 280
    local barH = cfg.barHeight or 16
    local alignRight = cfg.alignTexts == "right"

    local scale = cfg.frameScale or 1.0
    f.root:SetScale(scale)

    local point = getConfig("overlay.point")
    local x = getConfig("overlay.x")
    local y = getConfig("overlay.y")
    if point and x and y then
        f.root:SetPoint(point, UIParent, point, x, y)
    else
        f.root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    local anchor = alignRight and "TOPRIGHT" or "TOPLEFT"
    local padX = alignRight and -pad or pad

    local curY = -pad

    f.deathsText:SetFont(getFont("overlay.deathsFont"), cfg.deathsFontSize or 14, cfg.deathsFontFlags or "OUTLINE")
    local dr, dg, db, da = hexToRGB(cfg.deathsColor)
    f.deathsText:SetTextColor(dr, dg, db, da)
    f.deathsText:SetJustifyH(alignRight and "RIGHT" or "LEFT")
    f.deathsText:SetText(" ")
    f.deathsText:ClearAllPoints()
    f.deathsText:SetPoint(anchor, f.root, anchor, padX, curY)
    curY = curY - f.deathsText:GetStringHeight() - vOff

    f.timerText:SetFont(getFont("overlay.timerFont"), cfg.timerFontSize or 20, cfg.timerFontFlags or "OUTLINE")
    local tr, tg, tb, ta = hexToRGB(cfg.timerRunningColor)
    f.timerText:SetTextColor(tr, tg, tb, ta)
    f.timerText:SetJustifyH(alignRight and "RIGHT" or "LEFT")
    f.timerText:SetText("0:00 / 0:00")
    f.timerText:ClearAllPoints()
    f.timerText:SetPoint(anchor, f.root, anchor, padX, curY)
    curY = curY - f.timerText:GetStringHeight() - vOff

    f.timerSplitText:SetFont(getFont("overlay.timerFont"), (cfg.timerFontSize or 20) * 0.6, cfg.timerFontFlags or "OUTLINE")
    f.timerSplitText:SetJustifyH(alignRight and "RIGHT" or "LEFT")
    f.timerSplitText:ClearAllPoints()
    f.timerSplitText:Hide()

    f.keyText:SetFont(getFont("overlay.keyFont"), cfg.keyFontSize or 14, cfg.keyFontFlags or "OUTLINE")
    local kr, kg, kb, ka = hexToRGB(cfg.keyColor)
    f.keyText:SetTextColor(kr, kg, kb, ka)
    f.keyText:SetJustifyH(alignRight and "RIGHT" or "LEFT")
    f.keyText:SetText("[0]")

    f.keyDetailsText:SetFont(getFont("overlay.keyDetailsFont"), cfg.keyDetailsFontSize or 14, cfg.keyDetailsFontFlags or "OUTLINE")
    local kdr, kdg, kdb, kda = hexToRGB(cfg.keyDetailsColor)
    f.keyDetailsText:SetTextColor(kdr, kdg, kdb, kda)
    f.keyDetailsText:SetJustifyH(alignRight and "RIGHT" or "LEFT")
    f.keyDetailsText:SetText("")

    local kH = math_max(f.keyText:GetStringHeight(), 14)
    local kdH = math_max(f.keyDetailsText:GetStringHeight(), 14)
    local rowH = math_max(kH, kdH)

    f.keyText:ClearAllPoints()
    f.keyDetailsText:ClearAllPoints()
    if alignRight then
        f.keyDetailsText:SetPoint("TOPRIGHT", f.root, "TOPRIGHT", -pad, curY)
        f.keyText:SetPoint("TOPRIGHT", f.keyDetailsText, "TOPLEFT", -3, 0)
    else
        f.keyText:SetPoint("TOPLEFT", f.root, "TOPLEFT", pad, curY)
        f.keyDetailsText:SetPoint("TOPLEFT", f.keyText, "TOPRIGHT", 3, 0)
    end
    curY = curY - rowH - vOff

    local timerBarOffset = 2
    local timeLimits = SMPState:Get().timeLimits
    local fractions = {}
    for i = 1, 3 do
        local barMax = (timeLimits[i] or 0) - (timeLimits[i + 1] or 0)
        fractions[i] = barMax > 0 and barMax / (timeLimits[1] or 1) or (i == 1 and 0.6 or 0.2)
    end

    local tr2, tg2, tb2 = hexToRGB(cfg.timerRunningColor)

    local b3W = barW * fractions[3] - timerBarOffset
    self:SetBarLayout(f.bar3, "overlay.bar3Texture", cfg.bar3TextureColor, b3W, barH, 0, 0)
    f.bar3.text:SetFont(getFont("overlay.bar3Font"), cfg.bar3FontSize or 14, cfg.bar3FontFlags or "OUTLINE")
    f.bar3.text:SetTextColor(tr2, tg2, tb2)
    f.bar3.text:SetJustifyH("LEFT")
    f.bar3.text:ClearAllPoints()
    f.bar3.text:SetPoint("LEFT", f.bar3, "LEFT", 4, 0)

    local b2W = barW * fractions[2] - timerBarOffset
    self:SetBarLayout(f.bar2, "overlay.bar2Texture", cfg.bar2TextureColor, b2W, barH, b3W + timerBarOffset, 0)
    f.bar2.text:SetFont(getFont("overlay.bar2Font"), cfg.bar2FontSize or 14, cfg.bar2FontFlags or "OUTLINE")
    f.bar2.text:SetTextColor(tr2, tg2, tb2)
    f.bar2.text:SetJustifyH("LEFT")
    f.bar2.text:ClearAllPoints()
    f.bar2.text:SetPoint("LEFT", f.bar2, "LEFT", 4, 0)

    local b1W = barW * fractions[1] - timerBarOffset
    self:SetBarLayout(f.bar1, "overlay.bar1Texture", cfg.bar1TextureColor, b1W, barH, b3W + b2W + timerBarOffset * 2, 0)
    f.bar1.text:SetFont(getFont("overlay.bar1Font"), cfg.bar1FontSize or 14, cfg.bar1FontFlags or "OUTLINE")
    f.bar1.text:SetTextColor(tr2, tg2, tb2)
    f.bar1.text:SetJustifyH("LEFT")
    f.bar1.text:ClearAllPoints()
    f.bar1.text:SetPoint("LEFT", f.bar1, "LEFT", 4, 0)

    f.bars:SetSize(barW, barH)
    f.bars:ClearAllPoints()
    f.bars:SetPoint(anchor, f.root, anchor, padX, curY)
    curY = curY - barH - vOff

    self:SetBarLayout(f.forces, "overlay.forcesTexture", cfg.forcesTextureColor, barW, barH, 0, 0)

    local ofr, ofg, ofb = hexToRGB(cfg.forcesOverlayTextureColor)
    f.forcesOverlay:SetMinMaxValues(0, 1)
    f.forcesOverlay:SetValue(0)
    f.forcesOverlay:ClearAllPoints()
    f.forcesOverlay:SetSize(barW - 2, barH - 2)
    f.forcesOverlay:SetStatusBarTexture(getStatusBarTexture("overlay.forcesOverlayTexture"))
    f.forcesOverlay:SetStatusBarColor(ofr, ofg, ofb, 0.7)
    f.forcesOverlay:SetPoint("LEFT", f.forces, "LEFT", 1, 0)

    f.forces.text:SetFont(getFont("overlay.forcesFont"), cfg.forcesFontSize or 14, cfg.forcesFontFlags or "OUTLINE")
    local fr, fg, fb = hexToRGB(cfg.forcesColor)
    f.forces.text:SetTextColor(fr, fg, fb)
    f.forces.text:SetJustifyH("LEFT")
    f.forces.text:ClearAllPoints()
    f.forces.text:SetPoint("LEFT", f.forces, "LEFT", 4, 0)

    f.forces:ClearAllPoints()
    f.forces:SetPoint(anchor, f.root, anchor, padX, curY)
    curY = curY - barH - vOff

    local oFont = getFont("overlay.objectivesFont")
    local oSize = cfg.objectivesFontSize or 14
    local oFlags = cfg.objectivesFontFlags or "OUTLINE"
    local ocr, ocg, ocb = hexToRGB(cfg.objectivesColor)
    for i = 1, MAX_OBJECTIVES do
        f.objectiveTexts[i]:SetFont(oFont, oSize, oFlags)
        f.objectiveTexts[i]:SetTextColor(ocr, ocg, ocb)
        f.objectiveTexts[i]:SetJustifyH(alignRight and "RIGHT" or "LEFT")
        f.objectiveTexts[i]:ClearAllPoints()
        f.objectiveTexts[i]:SetPoint(anchor, f.root, anchor, padX, curY)
        f.objectiveTexts[i]:SetText("")
        curY = curY - oSize - objOff
    end

    curY = curY + objOff - pad

    f.root:SetWidth(barW + pad * 2)
    f.root:SetHeight(math_abs(curY))

    f.bg:ClearAllPoints()
    f.bg:SetAllPoints(f.root)

    self:RenderTimer()
    self:RenderForces()
    self:RenderObjectives()
end

function SMPFrame:SetBarLayout(bar, texPath, colorHex, width, height, xOffset, yOffset)
    bar:SetSize(width, height)
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", xOffset, yOffset)
    bar:SetStatusBarTexture(getStatusBarTexture(texPath))
    local r, g, b, a = hexToRGB(colorHex)
    bar:SetStatusBarColor(r, g, b, a)
    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { top = 1, right = 1, bottom = 1, left = 1 },
        })
        bar:SetBackdropColor(0, 0, 0, 0.5)
        bar:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

function SMPFrame:RenderTimer()
    local f = private.frames
    if not f.root then return end

    local state = SMPState:Get()
    local cfg = SMPConfig.db.profile.overlay

    local timeLimit = state.timeLimit
    local timer = state.timer
    local timerText = formatTime(timer) .. " / " .. formatTime(timeLimit)

    if state.completed then
        local compTime = state.completionTimeMs and state.completionTimeMs / 1000 or timer
        if cfg.showMillisecondsWhenDungeonCompleted and state.completionTimeMs then
            local ms = state.completionTimeMs
            timerText = format("%d:%02d.%03d", floor(ms / 60000), floor(ms / 1000) % 60, ms % 1000)
            timerText = timerText .. " / " .. formatTime(timeLimit)
        else
            timerText = formatTime(compTime) .. " / " .. formatTime(timeLimit)
        end
        local color = state.completedOnTime and cfg.timerSuccessColor or cfg.timerExpiredColor
        timerText = colorText(timerText, color)
    end

    f.timerText:SetText(timerText)

    local timeLimits = state.timeLimits
    local tr, tg, tb, ta = hexToRGB(cfg.timerRunningColor)
    if state.completed then
        local color = state.completedOnTime and cfg.timerSuccessColor or cfg.timerExpiredColor
        tr, tg, tb, ta = hexToRGB(color)
    end

    local bars = { f.bar1, f.bar2, f.bar3 }
    for i = 1, 3 do
        local barLimit = timeLimits[i] or 0
        local timeRemaining = barLimit - timer
        local barMax = barLimit - (timeLimits[i + 1] or 0)
        local barElapsed = barMax - timeRemaining
        local barValue = clamp(barElapsed / (barMax > 0 and barMax or 1), 0, 1)

        bars[i]:SetValue(barValue)

        local timeText = formatTime(math_abs(timeRemaining))
        if not state.completed then
            if i == 1 and timeRemaining < 0 then
                timeText = "-" .. timeText
            elseif i ~= 1 and timeRemaining < 0 then
                timeText = ""
            end
        else
            timeText = (timeRemaining <= 0 and "-" or "") .. timeText
        end

        bars[i].text:SetText(timeText)
        bars[i].text:SetTextColor(tr, tg, tb, ta)
    end
end

function SMPFrame:RenderForces()
    local f = private.frames
    if not f.root then return end

    local state = SMPState:Get()
    local cfg = SMPConfig.db.profile.overlay

    local percent = state.forcesPercent
    local barW = cfg.barWidth or 280

    local overlayOffset = 1 + barW * (percent / 100)
    f.forcesOverlay:ClearAllPoints()
    f.forcesOverlay:SetPoint("LEFT", f.forces, "LEFT", overlayOffset, 0)
    f.forcesOverlay:SetValue(state.pullPercent > 0 and clamp(state.pullPercent, 0, 1 - percent / 100) or 0)
    f.forces:SetValue(percent / 100)

    local forcesText = self:FormatForcesText(percent, state, cfg)
    if state.pullPercent and state.pullPercent > 0 then
        local pullText = self:FormatPullText(state, cfg)
        if pullText and pullText ~= "" then
            forcesText = pullText .. " " .. forcesText
        end
    end
    if state.forcesCompleted then
        forcesText = colorText(forcesText, cfg.completedForcesColor)
    end
    f.forces.text:SetText(forcesText)

    if not LCG then return end

    local inCombat = InCombatLockdown() or state.demoModeActive
    local percentBeforePull = percent / 100
    local percentAfterPull = percentBeforePull + (state.pullPercent or 0)
    local wouldComplete = percentBeforePull < 1 and percentAfterPull >= 1.0
    local hasPull = inCombat and state.pullPercent > 0 and not state.forcesCompleted

    local newGlowType = nil
    if wouldComplete and not state.forcesCompleted then
        newGlowType = "complete"
    elseif hasPull then
        newGlowType = "combat"
    end

    if newGlowType ~= private.glowType then
        if private.glowActive and LCG then
            LCG.AutoCastGlow_Stop(f.forces, "SMPForcesGlow")
        end

        if newGlowType and LCG then
            if newGlowType == "complete" then
                LCG.AutoCastGlow_Start(f.forces, { 0.2, 0.8, 1.0, 0.9 }, 12, 0.5, 0.7, 0, 0, "SMPForcesGlow")
            else
                LCG.AutoCastGlow_Start(f.forces, { 1.0, 0.2, 0.2, 0.9 }, 6, 0.4, 0.7, 0, 0, "SMPForcesGlow")
            end
        end

        private.glowActive = newGlowType ~= nil
        private.glowType = newGlowType
    end
end

function SMPFrame:FormatForcesText(percent, state, cfg)
    local formatStr = cfg.forcesFormat or ":percent:"
    if formatStr == ":custom:" then
        formatStr = cfg.customForcesFormat or ":percent:"
    end

    local totalForces = SMPForcesData:GetTotal(state.mapId) or 900
    local count = floor(totalForces * percent / 100)
    local remaining = totalForces - count
    local remainingPercent = 100 - percent

    formatStr = formatStr:gsub(":percent:", format("%.2f%%", percent))
    formatStr = formatStr:gsub(":count:", tostring(count))
    formatStr = formatStr:gsub(":totalcount:", tostring(totalForces))
    formatStr = formatStr:gsub(":remainingcount:", tostring(remaining))
    formatStr = formatStr:gsub(":remainingpercent:", format("%.2f%%", remainingPercent))

    return formatStr
end

function SMPFrame:FormatPullText(state, cfg)
    local formatStr = cfg.currentPullFormat or "(+:percent:)"
    if formatStr == ":custom:" then
        formatStr = cfg.customCurrentPullFormat or "(+:percent:)"
    end

    local totalForces = SMPForcesData:GetTotal(state.mapId) or 900
    local pullCount = floor(totalForces * (state.pullPercent or 0))
    local pullPercent = (state.pullPercent or 0) * 100

    formatStr = formatStr:gsub(":percent:", format("+%.2f%%", pullPercent))
    formatStr = formatStr:gsub(":count:", tostring(pullCount))

    return formatStr
end

function SMPFrame:RenderSplits(splits)
    local f = private.frames
    if not f.root then return end

    if not SMPConfig:GetProfileConfig("overlay.splitsEnabled") then
        f.timerSplitText:Hide()
        return
    end

    if not splits then return end

    local latestDiff = nil
    for _, split in pairs(splits) do
        if split.diff then
            latestDiff = split.diff
        end
    end

    if latestDiff then
        local sign = latestDiff <= 0 and "-" or "+"
        local absDiff = math.abs(latestDiff)
        local text = format("%s%d:%02d", sign, floor(absDiff / 60), floor(absDiff % 60))

        local colorHex = latestDiff <= 0
            and (SMPConfig:GetProfileConfig("overlay.splitFasterTimeColor") or "FF00FF00")
            or (SMPConfig:GetProfileConfig("overlay.splitSlowerTimeColor") or "FFFF2020")

        f.timerSplitText:SetText(colorText(text, colorHex))
        f.timerSplitText:Show()
    else
        f.timerSplitText:Hide()
    end
end

function SMPFrame:RenderObjectives()
    local f = private.frames
    if not f.root then return end

    local state = SMPState:Get()
    local cfg = SMPConfig.db.profile.overlay
    local alignStart = cfg.alignBossClear == "start"

    for i = 1, MAX_OBJECTIVES do
        f.objectiveTexts[i]:SetText("")
    end

    for i, boss in ipairs(state.bosses) do
        if i > MAX_OBJECTIVES then break end
        local str = boss.name

        if boss.killTime then
            local killStr = formatTime(boss.killTime)
            if alignStart then
                str = colorText(killStr, cfg.completedObjectivesColor) .. " " .. colorText(str, cfg.completedObjectivesColor)
            else
                str = colorText(str, cfg.completedObjectivesColor) .. " " .. colorText(killStr, cfg.completedObjectivesColor)
            end
        end

        f.objectiveTexts[i]:SetText(str)
    end
end

function SMPFrame:Show()
    private.frames.root:Show()
end

function SMPFrame:Hide()
    if private.glowActive and LCG then
        LCG.AutoCastGlow_Stop(private.frames.forces, "SMPForcesGlow")
        private.glowActive = false
        private.glowType = nil
    end
    private.frames.root:Hide()
end

function SMPFrame:IsShown()
    return private.frames.root and private.frames.root:IsShown()
end

function SMPFrame:SetUnlocked(unlocked)
    private.isUnlocked = unlocked
    local f = private.frames
    if not f.bg then return end
    if unlocked then
        f.bg:SetVertexColor(0, 0, 0, 0.3)
    else
        f.bg:SetVertexColor(0, 0, 0, 0)
    end
    f.root:SetMovable(unlocked)
    f.root:EnableMouse(unlocked)
end

function SMPFrame:IsUnlocked()
    return private.isUnlocked
end

function SMPFrame:InvalidateTextures()
    statusBarTextureResolved = false
    statusBarTextureCache = nil
end

function SMPFrame:Initialize()
    private:CreateFrames()
    self:RenderLayout()

    SMPMessageBus.shared:RegisterRepeating("ChallengeStarted", function()
        self:Show()
        self:RenderLayout()
    end)

    SMPMessageBus.shared:RegisterRepeating("ChallengeCompleted", function()
        self:RenderTimer()
        self:RenderObjectives()
    end)

    SMPMessageBus.shared:RegisterRepeating("ChallengeStopped", function()
        self:Hide()
    end)

    SMPMessageBus.shared:RegisterRepeating("TimerTick", function()
        self:RenderTimer()
    end)

    SMPMessageBus.shared:RegisterRepeating("BossesUpdated", function()
        self:RenderObjectives()
    end)

    SMPMessageBus.shared:RegisterRepeating("ForcesUpdated", function()
        self:RenderForces()
    end)

    SMPMessageBus.shared:RegisterRepeating("PullUpdated", function()
        self:RenderForces()
    end)

    SMPMessageBus.shared:RegisterRepeating("SplitsUpdated", function(splits)
        self:RenderSplits(splits)
    end)

    SMPMessageBus.shared:RegisterRepeating("DeathsUpdated", function()
        local state = SMPState:Get()
        local count, timeLost = state.deathCount, state.deathTimeLost
        local text = " "
        if count > 0 then
            text = tostring(count) .. " Смерт" .. (count ~= 1 and "ей" or "и")
            if timeLost > 0 then
                if timeLost < 60 then
                    text = text .. " (+" .. tostring(timeLost) .. "с)"
                else
                    text = text .. " (+" .. formatTime(timeLost) .. ")"
                end
            end
        end
        private.frames.deathsText:SetText(text)
    end)

    SMPMessageBus.shared:RegisterRepeating("ChallengeStateChanged", function()
        local state = SMPState:Get()

        if state.level > 0 then
            private.frames.keyText:SetText(format("[%d]", state.level))
        else
            private.frames.keyText:SetText("[0]")
        end

        local affixNames = {}
        for _, affix in ipairs(state.affixes) do
            affixNames[#affixNames + 1] = affix.name
        end

		private.frames.keyDetailsText:SetText(table.concat(affixNames, " - "))

        local count, timeLost = state.deathCount, state.deathTimeLost
        local text = " "
        if count and count > 0 then
            text = tostring(count) .. " Смерт" .. (count ~= 1 and "ей" or "и")
            if timeLost and timeLost > 0 then
                if timeLost < 60 then
                    text = text .. " (+" .. tostring(timeLost) .. "s)"
                else
                    text = text .. " (+" .. formatTime(timeLost) .. ")"
                end
            end
        end
        private.frames.deathsText:SetText(text)

        self:RenderForces()
        self:RenderObjectives()
        self:RenderTimer()
    end)

    SMPMessageBus.shared:RegisterRepeating("OverlayConfigChanged", function()
        self:RenderLayout()
    end)

    private.frames.deathsHitArea = CreateFrame("Frame", nil, private.frames.root)
    private.frames.deathsHitArea:SetAllPoints(private.frames.deathsText)
    private.frames.deathsHitArea:EnableMouse(true)
    private.frames.deathsHitArea:SetScript("OnEnter", function(self)
        if not SMPConfig:GetProfileConfig("overlay.showDeathsTooltip") then return end

        local state = SMPState:Get()
        if not state.inChallenge then return end

        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Смерти", 1, 0.82, 0)

        local style = SMPConfig:GetProfileConfig("overlay.deathLogStyle") or "time"

        if style == "count" then
            local sorted = {}
            for name, data in pairs(state.deathDetails) do
                sorted[#sorted + 1] = { name = name, count = data.count }
            end
            table.sort(sorted, function(a, b) return a.count > b.count end)

            for _, entry in ipairs(sorted) do
                GameTooltip:AddDoubleLine(entry.name, "x" .. entry.count, 1, 1, 1, 1, 0.2, 0.2)
            end
        else
            local allDeaths = {}
            for name, data in pairs(state.deathDetails) do
                for _, ts in ipairs(data.timestamps) do
                    allDeaths[#allDeaths + 1] = { name = name, time = ts }
                end
            end
            table.sort(allDeaths, function(a, b) return a.time < b.time end)

            for _, entry in ipairs(allDeaths) do
                local timeStr = formatTime(entry.time)
                GameTooltip:AddDoubleLine(timeStr, entry.name, 0.8, 0.8, 0.8, 1, 0.2, 0.2)
            end
        end

        if not next(state.deathDetails) then
            GameTooltip:AddLine("Нет смертей", 0.5, 0.5, 0.5)
        end

        GameTooltip:Show()
    end)

    private.frames.deathsHitArea:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self:Hide()
end
