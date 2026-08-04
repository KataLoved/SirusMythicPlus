local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

---@class SMPLib
local SMPLib = SMPLoader:CreateModule("SMPLib")

local addonName = "SirusMythicPlus"
local cachedVersion

SMPLib.AddonPath = "Interface\\Addons\\" .. addonName .. "\\"

local unpack = unpack

---@return number, number, number
function SMPLib:GetAddonVersionInfo()
    if not cachedVersion then
        cachedVersion = GetAddOnMetadata(addonName, "Version")
    end
    local major, minor, patch = cachedVersion:match("(%d+)%p(%d+)%p(%d+)")
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function SMPLib:GetAddonVersionString()
    if not cachedVersion then
        cachedVersion = GetAddOnMetadata(addonName, "Version")
    end
    return "v" .. cachedVersion
end

function SMPLib:Count(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local REALM_SLUG_CACHE = nil

local function detectRealmSlug()
    -- local realm = GetRealmName() or ""
    -- local slug = realm:match("[Xx]%d+$") or realm:match("[Xx]%d+")
    -- if slug then return slug:lower() end
    -- local MULTI = { ["Soulseeker"] = "x1", ["Neverest"] = "x3", ["Sirus"] = "x5" }
    -- local base = realm:match("^(%S+)")
    -- if base and MULTI[base] then return MULTI[base] end
    return "x3"
end

function SMPLib:GetRealmSlug()
    if not REALM_SLUG_CACHE then
        REALM_SLUG_CACHE = detectRealmSlug()
    end
    return REALM_SLUG_CACHE
end

function SMPLib:GetProfileURL(playerName)
    return "https://sirus.su/base/character/" .. self:GetRealmSlug() .. "/" .. playerName
end

local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"

function SMPLib:FetchFont(fontName)
    if not fontName or fontName == "" then return DEFAULT_FONT_PATH end
    local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
    if ok and lsm then
        local path = lsm:Fetch("font", fontName)
        if path then return path end
    end
    return DEFAULT_FONT_PATH
end

local SCORE_MIN = 0
local SCORE_MAX = 2500

local SCORE_STOPS = {
    { 0.00, 0.12, 0.80, 0.20 },
    { 0.35, 0.00, 0.44, 0.87 },
    { 0.65, 0.64, 0.21, 0.93 },
    { 1.00, 1.00, 0.50, 0.00 },
}

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function toByte01(x)
    return math.floor(clamp(x, 0, 1) * 255 + 0.5)
end

local function rgbToHex(r, g, b)
    return ("|cff%02x%02x%02x"):format(toByte01(r), toByte01(g), toByte01(b))
end

function SMPLib:ScoreColor(score)
    score = tonumber(score or 0) or 0
    local t = clamp((score - SCORE_MIN) / (SCORE_MAX - SCORE_MIN), 0, 1)
    local prev = SCORE_STOPS[1]
    for i = 2, #SCORE_STOPS do
        local cur = SCORE_STOPS[i]
        if t <= cur[1] then
            local span = cur[1] - prev[1]
            local lt = (span > 0) and ((t - prev[1]) / span) or 0
            return rgbToHex(lerp(prev[2], cur[2], lt), lerp(prev[3], cur[3], lt), lerp(prev[4], cur[4], lt))
        end
        prev = cur
    end
    local last = SCORE_STOPS[#SCORE_STOPS]
    return rgbToHex(last[2], last[3], last[4])
end

function SMPLib:ScoreColorRGB(score)
    score = tonumber(score or 0) or 0
    local t = clamp((score - SCORE_MIN) / (SCORE_MAX - SCORE_MIN), 0, 1)
    local prev = SCORE_STOPS[1]
    for i = 2, #SCORE_STOPS do
        local cur = SCORE_STOPS[i]
        if t <= cur[1] then
            local span = cur[1] - prev[1]
            local lt = (span > 0) and ((t - prev[1]) / span) or 0
            return { lerp(prev[2], cur[2], lt), lerp(prev[3], cur[3], lt), lerp(prev[4], cur[4], lt) }
        end
        prev = cur
    end
    local last = SCORE_STOPS[#SCORE_STOPS]
    return { last[2], last[3], last[4] }
end

function SMPLib:KeyColor(level)
    level = tonumber(level or 0) or 0
    if level >= 15 then return "|cffffd100"
    elseif level >= 10 then return "|cffa335ee"
    else return "|cff0070dd" end
end

function SMPLib:KeyColorRGB(level)
    level = tonumber(level or 0) or 0
    if level >= 15 then return { 1.0, 0.82, 0.0 }
    elseif level >= 10 then return { 0.64, 0.21, 0.93 }
    else return { 0.0, 0.44, 0.87 } end
end

function SMPLib:RankColor(rank)
    if not rank then return "|cff808080" end
    if rank <= 20 then return "|cffffd100"
    elseif rank <= 100 then return "|cffff8000"
    elseif rank <= 1000 then return "|cffa335ee"
    elseif rank <= 2000 then return "|cff19bb53"
    else return "|cff808080" end
end

function SMPLib:RankColorRGB(rank)
    if not rank then return { 0.5, 0.5, 0.5 } end
    if rank <= 20 then return { 1.0, 0.82, 0.0 }
    elseif rank <= 100 then return { 1.0, 0.5, 0.0 }
    elseif rank <= 1000 then return { 0.64, 0.21, 0.93 }
	elseif rank <= 2000 then return { 0.09, 0.73, 0.32 }
    else return { 0.5, 0.5, 0.5 } end
end

function SMPLib:ClassColorRGB(classID)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classID]
    if color then return { color.r, color.g, color.b } end
    return { 1, 1, 1 }
end

function SMPLib.spread(t, ...)
    return unpack(t), ...
end

SMPLib.Colors = {
    BRAND         = { 0.09, 0.52, 0.82 },
    PURPLE        = { 0.46, 0.33, 0.55 },
    PURPLE_LIGHT  = { 0.69, 0.55, 0.82 },
    BG_DARK       = { 0.055, 0.047, 0.067 },
    BG_PANEL      = { 0.04, 0.035, 0.05 },
    BG_ROW        = { 0.075, 0.065, 0.085 },
    BG_ROW_HOVER  = { 0.11, 0.09, 0.13 },
    BG_ROW_SEL    = { 0.09, 0.12, 0.17 },
    BORDER_PURPLE = { 0.46, 0.33, 0.55, 0.5 },
    GREEN         = { 0.33, 0.78, 0.47 },
    RED           = { 0.85, 0.33, 0.33 },
    GRAY          = { 0.47, 0.47, 0.47 },
    WHITE         = { 1, 1, 1 },
    GOLD          = { 1.0, 0.82, 0.0 },
}

return SMPLib
