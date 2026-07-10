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

return SMPLib
