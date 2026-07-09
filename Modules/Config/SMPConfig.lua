---@class SMPConfig
local SMPConfig = SMPLoader:CreateModule("SMPConfig")

---@type SMPConfigDefaults
local SMPConfigDefaults = SMPLoader:ImportModule("SMPConfigDefaults")

local SCOPES = {
    global = "global",
    profile = "profile",
}

local function getScopeRoot(scope)
    if scope == SCOPES.global then
        return SMPConfig.db.global
    elseif scope == SCOPES.profile then
        return SMPConfig.db.profile
    end
    error("SMPConfig: unknown scope '" .. tostring(scope) .. "'", 3)
end

local function splitPath(path)
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        parts[#parts + 1] = part
    end
    if #parts == 0 then
        error("SMPConfig: empty path", 3)
    end
    return parts
end

local function traverse(root, path, createMissing)
    local node = root
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then
            if createMissing then
                node[key] = {}
            else
                return nil, path[#path]
            end
        end
        node = node[key]
    end
    return node, path[#path]
end

local function getOptions()
    return {
        type = "group",
        name = "|cff00ff00Sirus|r|cffffffffMythicPlus|r",
        args = {
            tooltip = {
                type = "group",
                name = "Tooltip",
                inline = true,
                args = {
                    showSeparator = {
                        type = "toggle",
                        name = "Показывать разделитель",
                        desc = "Пустая строка перед заголовком Mythic+",
                        get = function() return SMPConfig:GetProfileConfig("tooltip.showSeparator") end,
                        set = function(_, v) SMPConfig:UpdateProfileConfig("tooltip.showSeparator", v) end,
                        order = 1,
                    },
                    showDungeonListAlways = {
                        type = "toggle",
                        name = "Всегда показывать список инстов",
                        desc = "Показывать список всех инстов без Shift",
                        get = function() return SMPConfig:GetProfileConfig("tooltip.showDungeonListAlways") end,
                        set = function(_, v) SMPConfig:UpdateProfileConfig("tooltip.showDungeonListAlways", v) end,
                        order = 2,
                    },
                    abbreviateDungeons = {
                        type = "toggle",
                        name = "Сокращать названия инстов",
                        desc = "Бастионы Адского Пламени > БАП",
                        get = function() return SMPConfig:GetProfileConfig("tooltip.abbreviateDungeons") end,
                        set = function(_, v) SMPConfig:UpdateProfileConfig("tooltip.abbreviateDungeons", v) end,
                        order = 3,
                    },
                },
            },
        },
    }
end

function SMPConfig:Initialize()
    if self.db then
        return
    end

    self.db = LibStub("AceDB-3.0"):New("SMPConfigDB", SMPConfigDefaults:Load(), true)

    SMP.db = self.db

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    self:RunMigrations()
    self:RegisterOptions()
end

function SMPConfig:RegisterOptions()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    AceConfig:RegisterOptionsTable("SirusMythicPlus", getOptions)
    AceConfigDialog:AddToBlizOptions("SirusMythicPlus", "|cff00ff00Sirus|r|cffffffffMythicPlus|r")
end

function SMPConfig:RunMigrations()
    local version = self.db.global.dbVersion or 0
    if version < 1 then
        self.db.global.dbVersion = 1
    end
end

function SMPConfig:Get(path, scope)
    local root = getScopeRoot(scope or SCOPES.profile)
    local node, key = traverse(root, splitPath(path), false)
    if not node then
        return nil
    end
    return node[key]
end

function SMPConfig:Set(path, value, scope)
    local root = getScopeRoot(scope or SCOPES.profile)
    local node, key = traverse(root, splitPath(path), true)
    node[key] = value
    return value
end

function SMPConfig:UpdateProfileConfig(path, value)
    return self:Set(path, value, SCOPES.profile)
end

function SMPConfig:GetProfileConfig(path)
    return self:Get(path, SCOPES.profile)
end

function SMPConfig:GetGlobalConfig(path)
    return self:Get(path, SCOPES.global)
end

function SMPConfig:UpdateGlobalConfig(path, value)
    return self:Set(path, value, SCOPES.global)
end

function SMPConfig:OnProfileChanged()
    SMPMessageBus.shared:Fire("ConfigChanged")
end
