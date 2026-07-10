---@class SMPConfigDefaults
local SMPConfigDefaults = SMPLoader:CreateModule("SMPConfigDefaults")

function SMPConfigDefaults:Load()
    return {
        global = {
            dbVersion = 1,
        },
        profile = {
            tooltip = {
                showSeparator = true,
                showDungeonListAlways = false,
                abbreviateDungeons = false,
            },
        },
    }
end
