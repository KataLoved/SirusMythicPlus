---@class SMPConfig
local SMPConfig = SMPLoader:CreateModule("SMPConfig")

---@type SMPConfigDefaults
local SMPConfigDefaults = SMPLoader:ImportModule("SMPConfigDefaults")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

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

local function toggle(name, path, desc, order)
    return {
        type = "toggle",
        name = name,
        desc = desc,
        order = order,
        get = function() return SMPConfig:GetProfileConfig(path) end,
        set = function(_, v) SMPConfig:UpdateProfileConfig(path, v) end,
    }
end

local function range(name, path, min, max, step, desc, order)
    return {
        type = "range",
        name = name,
        desc = desc,
        order = order,
        min = min,
        max = max,
        step = step,
        get = function() return SMPConfig:GetProfileConfig(path) end,
        set = function(_, v) SMPConfig:UpdateProfileConfig(path, v) end,
    }
end

local function selectOpt(name, path, values, desc, order)
    return {
        type = "select",
        name = name,
        desc = desc,
        order = order,
        values = values,
        get = function() return SMPConfig:GetProfileConfig(path) end,
        set = function(_, v) SMPConfig:UpdateProfileConfig(path, v) end,
    }
end

local function fontSelect(name, path, desc, order)
    return {
        type = "select",
        name = name,
        desc = desc,
        order = order,
        dialogControl = "LSM30_Font",
        values = function()
            local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
            if ok and lsm then return lsm:HashTable("font") end
            return { ["Friz Quadrata TT"] = "Friz Quadrata TT" }
        end,
        get = function() return SMPConfig:GetProfileConfig(path) end,
        set = function(_, v) SMPConfig:UpdateProfileConfig(path, v) end,
    }
end

local function fontFlagsSelect(name, path, desc, order)
    return selectOpt(name, path, {
        ["OUTLINE"] = "Outline",
        ["OUTLINE, MONOCHROME"] = "Outline + Monochrome",
        ["THICKOUTLINE"] = "Thick Outline",
        ["MONOCHROME"] = "Monochrome",
        [""] = "None",
    }, desc, order)
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
                order = 1,
                args = {
                    showSeparator = toggle("Показывать разделитель", "tooltip.showSeparator", "Пустая строка перед заголовком Mythic+", 1),
                    showDungeonListAlways = toggle("Всегда показывать список инстов", "tooltip.showDungeonListAlways", "Показывать список всех инстов без Shift", 2),
                    abbreviateDungeons = toggle("Сокращать названия инстов", "tooltip.abbreviateDungeons", "Бастионы Адского Пламени > БАП", 3),
                },
            },
            search = {
                type = "group",
                name = "Поиск игроков",
                inline = true,
                order = 2,
                args = {
                    searchFont = fontSelect("Шрифт", "search.font", "Шрифт для окна поиска игроков", 1),
                    searchFontSize = range("Размер шрифта", "search.fontSize", 8, 24, 1, "Базовый размер шрифта в окне поиска", 2),
                    searchFontFlags = fontFlagsSelect("Флаги шрифта", "search.fontFlags", "Outline, Monochrome и т.д.", 3),
                },
            },
            profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(SMPConfig.db),
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
