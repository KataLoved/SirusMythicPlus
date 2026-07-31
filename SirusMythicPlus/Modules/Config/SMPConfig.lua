---@class SMPConfig
local SMPConfig = SMPLoader:CreateModule("SMPConfig")

---@type SMPConfigDefaults
local SMPConfigDefaults = SMPLoader:ImportModule("SMPConfigDefaults")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

---@type SMPCore
local SMPCore = SMPLoader:ImportModule("SMPCore")

---@type SMPFrame
local SMPFrame = SMPLoader:ImportModule("SMPFrame")

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

local function color(name, path, desc, order)
    return {
        type = "color",
        name = name,
        desc = desc,
        order = order,
        hasAlpha = true,
        get = function()
            local hex = SMPConfig:GetProfileConfig(path) or "FFFFFFFF"
            local r = tonumber(hex:sub(1, 2), 16) / 255
            local g = tonumber(hex:sub(3, 4), 16) / 255
            local b = tonumber(hex:sub(5, 6), 16) / 255
            local a = hex:len() >= 8 and tonumber(hex:sub(7, 8), 16) / 255 or 1
            return r, g, b, a
        end,
        set = function(_, r, g, b, a)
            local function toHex(v) return string.format("%02x", math.floor(v * 255 + 0.5)) end
            SMPConfig:UpdateProfileConfig(path, toHex(r) .. toHex(g) .. toHex(b) .. toHex(a))
        end,
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

local function input(name, path, desc, order)
    return {
        type = "input",
        name = name,
        desc = desc,
        order = order,
        width = "full",
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

local function statusBarSelect(name, path, desc, order)
    return {
        type = "select",
        name = name,
        desc = desc,
        order = order,
        dialogControl = "LSM30_Statusbar",
        values = function()
            local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0")
            if ok and lsm then return lsm:HashTable("statusbar") end
            return { ["Solid"] = "Solid" }
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

local function getOverlayOptions()
    return {
        type = "group",
        name = "Overlay",
        childGroups = "tab",
        order = 2,
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    insertKeystoneAutomatically = toggle("Авто-вставка ключа", "overlay.insertKeystoneAutomatically", "Автоматически вставлять ключа в гнездо", 1),
                    showMilliseconds = toggle("Мс после завершения", "overlay.showMillisecondsWhenDungeonCompleted", "Показывать миллисекунды после завершения ключа", 2),
                    showPullBar = toggle("Предсказание прогресса пулла", "overlay.showPullBar", "Показывать предсказание процентов текущего пулла (требуются новые индикаторы здоровья)", 3),
                    _sep1 = { type = "description", name = "", order = 4 },
                    nameplateStatus = {
                        type = "description",
                        name = "Новые индикаторы здоровья",
                        order = 5,
                    },
                    enableNewPlates = {
                        type = "execute",
                        name = "Включить новые плейты",
                        desc = "Включить новые индикаторы здоровья (требуется для предсказания прогресса).",
                        func = function()
                            SetCVar("nameplateEnableNew", "1")
                            SMP:Print("Новые индикаторы здоровья включены.")
                        end,
                        width = "double",
                        order = 6,
                    },
                    forcesGroup = {
                        type = "group",
                        name = "Текст прогресса",
                        inline = true,
                        order = 4,
                        args = {
                            forcesFormat = selectOpt("Формат", "overlay.forcesFormat", {
                                [":percent:"] = "82.52%",
                                [":count:/:totalcount:"] = "198/240",
                                [":count:/:totalcount: - :percent:"] = "198/240 - 82.52%",
                                [":custom:"] = "Кастомный",
                            }, nil, 1),
                            customForcesFormat = input("Кастомный формат", "overlay.customForcesFormat", ":percent: :count: :totalcount: :remainingcount: :remainingpercent:", 2),
                        },
                    },
                    pullGroup = {
                        type = "group",
                        name = "Текст пулла",
                        inline = true,
                        order = 5,
                        args = {
                            currentPullFormat = selectOpt("Формат", "overlay.currentPullFormat", {
                                ["(+:percent:)"] = "(+5.32%)",
                                ["(+:count:)"] = "(+14)",
                                ["(+:count: - :percent:)"] = "(+14 / 5.32%)",
                                [":custom:"] = "Кастомный",
                            }, nil, 1),
                            customCurrentPullFormat = input("Кастомный формат", "overlay.customCurrentPullFormat", nil, 2),
                        },
                    },
                    glowGroup = {
                        type = "group",
                        name = "Свечение",
                        inline = true,
                        order = 6,
                        args = {
                            showForcesGlow = toggle("Свечение при завершении пулла", "overlay.showForcesGlow", "Свечение когда текущий пулл доведёт до 100%", 1),
                            forcesGlowColor = color("Цвет свечения", "overlay.forcesGlowColor", nil, 3),
                            forcesGlowLineCount = range("Кол-во линий", "overlay.forcesGlowLineCount", 1, 30, 1, nil, 4),
                            forcesGlowLength = range("Длина линий", "overlay.forcesGlowLength", 1, 10, 1, nil, 5),
                            forcesGlowThickness = range("Толщина", "overlay.forcesGlowThickness", 1, 5, 0.1, nil, 6),
                            forcesGlowFrequency = range("Частота", "overlay.forcesGlowFrequency", 0.05, 0.5, 0.01, nil, 7),
                        },
                    },
                },
            },
            deaths = {
                type = "group",
                name = "Смерти",
                order = 2,
                args = {
                    showDeathsTooltip = toggle("Отображение смертей", "overlay.showDeathsTooltip", "Показывать лог смертей при наведении", 1),
                    deathLogStyle = selectOpt("Стиль лога", "overlay.deathLogStyle", {
                        ["time"] = "Со временем",
                        ["count"] = "По игрокам",
                    }, nil, 2),
                },
            },
            splits = {
                type = "group",
                name = "Сплиты",
                order = 3,
                args = {
                    splitsEnabled = toggle("Включить сплиты", "overlay.splitsEnabled", "Показывать время до лучших результатов", 1),
                    showSplitRecords = selectOpt("Показывать записи", "overlay.showSplitRecords", {
                        ["always"] = "Всегда",
                        ["countdown"] = "Перед стартом",
                        ["never"] = "Никогда",
                    }, nil, 2),
                    splitRecordsColor = color("Цвет записей", "overlay.splitRecordsColor", nil, 3),
                    fallbackSplitBehavior = selectOpt("Fallback уровень", "overlay.fallbackSplitBehavior", {
                        ["none"] = "Нет",
                        ["highest"] = "Лучший",
                        ["closest_higher"] = "Ближайший выше",
                        ["closest_lower"] = "Ближайший ниже",
                        ["lowest"] = "Худший",
                    }, "Если нет записи для текущего уровня", 4),
                    splitFasterTimeColor = color("Цвет (быстрее)", "overlay.splitFasterTimeColor", nil, 5),
                    splitSlowerTimeColor = color("Цвет (медленнее)", "overlay.splitSlowerTimeColor", nil, 6),
                },
            },
            display = {
                type = "group",
                name = "Отображение",
                order = 4,
                args = {
                    general = {
                        type = "group",
                        name = "Общее",
                        inline = true,
                        order = 1,
                        args = {
                            frameScale = range("Масштаб", "overlay.frameScale", 0.5, 2, 0.01, nil, 1),
                            framePadding = range("Отступ фрейма", "overlay.framePadding", 0, 40, 1, nil, 2),
                            alignTexts = selectOpt("Выравнивание текстов", "overlay.alignTexts", { ["left"] = "Лево", ["right"] = "Право" }, nil, 3),
                            alignBarTexts = selectOpt("Выравнивание на барах", "overlay.alignBarTexts", { ["left"] = "Лево", ["right"] = "Право" }, nil, 4),
                            alignBossClear = selectOpt("Позиция времени босса", "overlay.alignBossClear", { ["start"] = "Начало", ["end"] = "Конец" }, nil, 5),
                            verticalOffset = range("Отступ элементов", "overlay.verticalOffset", 0, 100, 0.5, nil, 6),
                            objectivesOffset = range("Отступ боссов", "overlay.objectivesOffset", 0, 100, 0.5, nil, 7),
                            barPadding = range("Отступ баров", "overlay.barPadding", 0, 100, 0.5, nil, 8),
                        },
                    },
                    timerColors = {
                        type = "group",
                        name = "Цвета таймера",
                        inline = true,
                        order = 2,
                        args = {
                            timerRunningColor = color("Цвет таймера", "overlay.timerRunningColor", "Во время рана", 1),
                            timerSuccessColor = color("Цвет успеха", "overlay.timerSuccessColor", nil, 2),
                            timerExpiredColor = color("Цвет провала", "overlay.timerExpiredColor", nil, 3),
                        },
                    },
                },
            },
            fonts = {
                type = "group",
                name = "Шрифты",
                order = 5,
                args = {
                    timer = {
                        type = "group",
                        name = "Таймер",
                        inline = true,
                        order = 1,
                        args = {
                            timerFont = fontSelect("Шрифт", "overlay.timerFont", nil, 1),
                            timerFontSize = range("Размер", "overlay.timerFontSize", 8, 80, 1, nil, 2),
                            timerFontFlags = fontFlagsSelect("Флаги", "overlay.timerFontFlags", nil, 3),
                        },
                    },
                    deaths = {
                        type = "group",
                        name = "Смерти",
                        inline = true,
                        order = 2,
                        args = {
                            deathsFont = fontSelect("Шрифт", "overlay.deathsFont", nil, 1),
                            deathsFontSize = range("Размер", "overlay.deathsFontSize", 8, 40, 1, nil, 2),
                            deathsFontFlags = fontFlagsSelect("Флаги", "overlay.deathsFontFlags", nil, 3),
                            deathsColor = color("Цвет", "overlay.deathsColor", nil, 4),
                        },
                    },
                    key = {
                        type = "group",
                        name = "Ключ",
                        inline = true,
                        order = 3,
                        args = {
                            keyFont = fontSelect("Шрифт", "overlay.keyFont", nil, 1),
                            keyFontSize = range("Размер", "overlay.keyFontSize", 8, 40, 1, nil, 2),
                            keyFontFlags = fontFlagsSelect("Флаги", "overlay.keyFontFlags", nil, 3),
                            keyColor = color("Цвет", "overlay.keyColor", nil, 4),
                        },
                    },
                    keyDetails = {
                        type = "group",
                        name = "Аффиксы",
                        inline = true,
                        order = 4,
                        args = {
                            keyDetailsFont = fontSelect("Шрифт", "overlay.keyDetailsFont", nil, 1),
                            keyDetailsFontSize = range("Размер", "overlay.keyDetailsFontSize", 8, 40, 1, nil, 2),
                            keyDetailsFontFlags = fontFlagsSelect("Флаги", "overlay.keyDetailsFontFlags", nil, 3),
                            keyDetailsColor = color("Цвет", "overlay.keyDetailsColor", nil, 4),
                        },
                    },
                    objectives = {
                        type = "group",
                        name = "Боссы",
                        inline = true,
                        order = 5,
                        args = {
                            objectivesFont = fontSelect("Шрифт", "overlay.objectivesFont", nil, 1),
                            objectivesFontSize = range("Размер", "overlay.objectivesFontSize", 8, 40, 1, nil, 2),
                            objectivesFontFlags = fontFlagsSelect("Флаги", "overlay.objectivesFontFlags", nil, 3),
                            objectivesColor = color("Цвет", "overlay.objectivesColor", nil, 4),
                            completedObjectivesColor = color("Цвет (убит)", "overlay.completedObjectivesColor", nil, 5),
                        },
                    },
                    forces = {
                        type = "group",
                        name = "Прогресс",
                        inline = true,
                        order = 6,
                        args = {
                            forcesFont = fontSelect("Шрифт", "overlay.forcesFont", nil, 1),
                            forcesFontSize = range("Размер", "overlay.forcesFontSize", 8, 40, 1, nil, 2),
                            forcesFontFlags = fontFlagsSelect("Флаги", "overlay.forcesFontFlags", nil, 3),
                            forcesColor = color("Цвет текста", "overlay.forcesColor", nil, 4),
                            completedForcesColor = color("Цвет (завершено)", "overlay.completedForcesColor", nil, 5),
                        },
                    },
                    timerBars = {
                        type = "group",
                        name = "Полосы таймера",
                        inline = true,
                        order = 7,
                        args = {
                            bar1 = {
                                type = "group",
                                name = "+1 (левая)",
                                inline = true,
                                order = 1,
                                args = {
                                    bar1Font = fontSelect("Шрифт", "overlay.bar1Font", nil, 1),
                                    bar1FontSize = range("Размер", "overlay.bar1FontSize", 8, 40, 1, nil, 2),
                                    bar1FontFlags = fontFlagsSelect("Флаги", "overlay.bar1FontFlags", nil, 3),
                                    bar1Texture = statusBarSelect("Текстура", "overlay.bar1Texture", nil, 4),
                                    bar1TextureColor = color("Цвет", "overlay.bar1TextureColor", nil, 5),
                                },
                            },
                            bar2 = {
                                type = "group",
                                name = "+2 (средняя)",
                                inline = true,
                                order = 2,
                                args = {
                                    bar2Font = fontSelect("Шрифт", "overlay.bar2Font", nil, 1),
                                    bar2FontSize = range("Размер", "overlay.bar2FontSize", 8, 40, 1, nil, 2),
                                    bar2FontFlags = fontFlagsSelect("Флаги", "overlay.bar2FontFlags", nil, 3),
                                    bar2Texture = statusBarSelect("Текстура", "overlay.bar2Texture", nil, 4),
                                    bar2TextureColor = color("Цвет", "overlay.bar2TextureColor", nil, 5),
                                },
                            },
                            bar3 = {
                                type = "group",
                                name = "+3 (правая)",
                                inline = true,
                                order = 3,
                                args = {
                                    bar3Font = fontSelect("Шрифт", "overlay.bar3Font", nil, 1),
                                    bar3FontSize = range("Размер", "overlay.bar3FontSize", 8, 40, 1, nil, 2),
                                    bar3FontFlags = fontFlagsSelect("Флаги", "overlay.bar3FontFlags", nil, 3),
                                    bar3Texture = statusBarSelect("Текстура", "overlay.bar3Texture", nil, 4),
                                    bar3TextureColor = color("Цвет", "overlay.bar3TextureColor", nil, 5),
                                },
                            },
                        },
                    },
                },
            },
            bars = {
                type = "group",
                name = "Бары",
                order = 6,
                args = {
                    barWidth = range("Ширина", "overlay.barWidth", 10, 600, 1, nil, 1),
                    barHeight = range("Высота", "overlay.barHeight", 4, 50, 1, nil, 2),
                    backdropTexture = statusBarSelect("Текстура фона", "overlay.backdropTexture", nil, 3),
                    backdropTextureColor = color("Цвет фона", "overlay.backdropTextureColor", nil, 4),
                    _sep1 = { type = "description", name = "", order = 5 },
                    forcesTexture = statusBarSelect("Текстура сил", "overlay.forcesTexture", nil, 6),
                    forcesTextureColor = color("Цвет прогресса", "overlay.forcesTextureColor", nil, 7),
                    forcesOverlayTexture = statusBarSelect("Текстура пулла", "overlay.forcesOverlayTexture", nil, 8),
                    forcesOverlayTextureColor = color("Цвет пулла", "overlay.forcesOverlayTextureColor", nil, 9),
                },
            },
            demo = {
                type = "group",
                name = "Демо",
                order = 7,
                args = {
                    desc = {
                        type = "description",
                        name = "Демо-режим показывает оверлей с тестовыми данными для настройки позиции и внешнего вида.\nКоманды: /smp demo, /smp unlock, /smp lock",
                        order = 1,
                    },
                    toggleDemo = {
                        type = "execute",
                        name = "Включить / Выключить демо",
                        desc = "Показать или скрыть тестовый оверлей",
                        func = function()
                            if SMPCore:IsDemoModeActive() then
                                SMPCore:DisableDemoMode()
                            else
                                SMPCore:EnableDemoMode()
                            end
                        end,
                        width = "double",
                        order = 2,
                    },
                    toggleLock = {
                        type = "execute",
                        name = "Разблокировать / Заблокировать",
                        desc = "Разрешить перемещение оверлея",
                        func = function()
                            SMPFrame:SetUnlocked(not SMPFrame:IsUnlocked())
                        end,
                        width = "double",
                        order = 3,
                    },
                },
            },
        },
    }
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
            overlay = getOverlayOptions(),
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
