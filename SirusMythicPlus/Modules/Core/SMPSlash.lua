---@class SMPSlash
local SMPSlash = SMPLoader:CreateModule("SMPSlash")

---@type SMPLib
local SMPLib = SMPLoader:ImportModule("SMPLib")

---@type SMPMinimapButton
local SMPMinimapButton = SMPLoader:ImportModule("SMPMinimapButton")

---@type SMPCore
local SMPCore = SMPLoader:ImportModule("SMPCore")

---@type SMPFrame
local SMPFrame = SMPLoader:ImportModule("SMPFrame")

---@type SMPPlayerSearch
local SMPPlayerSearch = SMPLoader:ImportModule("SMPPlayerSearch")

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

function SMPSlash:RegisterCommands()
    SMP:RegisterChatCommand("smp", function(input)
        SMPSlash:HandleCommand(input)
    end)
    SMP:RegisterChatCommand("mythicplus", function(input)
        SMPSlash:HandleCommand(input)
    end)
end

function SMPSlash:HandleCommand(input)
    input = input and input:match("^%s*(.-)%s*$") or ""

    if input == "" or input == "config" or input == "settings" then
        LibStub("AceConfigDialog-3.0"):Open("SirusMythicPlus")
        return
    end

    if input == "demo" then
        if SMPCore:IsDemoModeActive() then
            SMPCore:DisableDemoMode()
            SMP:Print("Демо-режим выключен.")
        else
            SMPCore:EnableDemoMode()
            SMP:Print("Демо-режим включен. |cff00ff00/smp demo|r для выключения.")
        end
        return
    end

    if input == "unlock" then
        SMPFrame:SetUnlocked(true)
        SMP:Print("Оверлей разблокирован. Перемещайте левой кнопкой мыши.")
        return
    end

    if input == "lock" then
        SMPFrame:SetUnlocked(false)
        SMP:Print("Оверлей заблокирован.")
        return
    end

    if input == "toggle" then
        SMPFrame:SetUnlocked(not SMPFrame:IsUnlocked())
        SMP:Print(SMPFrame:IsUnlocked() and "Оверлей разблокирован." or "Оверлей заблокирован.")
        return
    end

    if input == "minimap" or input == "minimap show" then
        SMPMinimapButton:Show()
        SMP:Print("|cff00ff00Sirus|r|cffffffffMythicPlus|r: кнопка на миникарте включена.")
        return
    end

    if input == "minimap hide" then
        SMPMinimapButton:Hide()
        SMP:Print("|cff00ff00Sirus|r|cffffffffMythicPlus|r: кнопка на миникарте скрыта.")
        return
    end

    if input == "version" or input == "ver" then
        SMP:Print("|cff00ff00Sirus|r|cffffffffMythicPlus|r " .. SMPLib:GetAddonVersionString())
        return
    end

    if input == "help" or input == "?" then
        SMPSlash:PrintHelp()
        return
    end

    if input == "check" then
        SMPCore:ForceCheck()
        return
    end

    if input == "poll" or input == "poll stop" then
        SMPCore:StopPolling()
        return
    end

    local searchName = input:match("^search%s+(.+)$")
    if searchName then
        SMPPlayerSearch:Show(searchName)
        return
    end

    if input == "debug" then
        SMPDebug:Toggle()
        return
    end

    if input == "log" then
        SMPDebug:ToggleWindow()
        return
    end

    local dumpCount = input:match("^dump%s*(%d*)$")
    if input == "dump" or dumpCount then
        local count = tonumber(dumpCount) or 20
        SMPDebug:DumpToChat(count)
        return
    end

    if input == "clear" then
        SMPDebug:Clear()
        SMP:Print("Лог очищен.")
        return
    end

    SMP:Print("Неизвестная команда. |cff00ff00/smp help|r")
end

function SMPSlash:PrintHelp()
    SMP:Print("|cff00ff00Sirus|r|cffffffffMythicPlus|r " .. SMPLib:GetAddonVersionString())
    SMP:Print("|cff00ff00/smp|r — открыть настройки")
    SMP:Print("|cff00ff00/smp demo|r — вкл/выкл демо-режим")
    SMP:Print("|cff00ff00/smp unlock|r — разблокировать оверлей")
    SMP:Print("|cff00ff00/smp lock|r — заблокировать оверлей")
    SMP:Print("|cff00ff00/smp toggle|r — переключить блокировку")
    SMP:Print("|cff00ff00/smp minimap|r — показать кнопку на миникарте")
    SMP:Print("|cff00ff00/smp check|r — принудительно проверить инст")
    SMP:Print("|cff00ff00/smp poll stop|r — остановить циклическую проверку")
    SMP:Print("|cff00ff00/smp search <имя>|r — поиск статистики игрока")
    SMP:Print("|cff00ff00/smp debug|r — вкл/выкл дебаг-логи")
    SMP:Print("|cff00ff00/smp log|r — открыть окно логов")
    SMP:Print("|cff00ff00/smp dump [N]|r — вывести последние N логов в чат")
    SMP:Print("|cff00ff00/smp clear|r — очистить лог")
    SMP:Print("|cff00ff00/smp version|r — версия аддона")
    SMP:Print("|cff00ff00/smp help|r — эта справка")
end
