local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

---@class SMPLib
local SMPLib = SMPLoader:CreateModule("SMPLib")

local addonName = "SirusMythicPlus"

SMPLib.AddonPath = "Interface\\Addons\\" .. addonName .. "\\"

local cachedVersion

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
    local realm = GetRealmName() or ""
    local slug = realm:match("[Xx]%d+$") or realm:match("[Xx]%d+")
    if slug then return slug:lower() end
    local MULTI = { ["Soulseeker"] = "x1", ["Neverest"] = "x3", ["Sirus"] = "x5" }
    local base = realm:match("^(%S+)")
    if base and MULTI[base] then return MULTI[base] end
    return "x5"
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

return SMPLib
