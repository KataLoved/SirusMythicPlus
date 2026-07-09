---@class SMPSlash
local SMPSlash = SMPLoader:CreateModule("SMPSlash")

---@type SMPLib
local SMPLib = SMPLoader:ImportModule("SMPLib")

---@type SMPMinimapButton
local SMPMinimapButton = SMPLoader:ImportModule("SMPMinimapButton")

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

    SMP:Print("Неизвестная команда. |cff00ff00/smp help|r")
end

function SMPSlash:PrintHelp()
    SMP:Print("|cff00ff00Sirus|r|cffffffffMythicPlus|r " .. SMPLib:GetAddonVersionString())
    SMP:Print("|cff00ff00/smp|r — открыть настройки")
    SMP:Print("|cff00ff00/smp minimap|r — показать кнопку на миникарте")
    SMP:Print("|cff00ff00/smp version|r — версия аддона")
    SMP:Print("|cff00ff00/smp help|r — эта справка")
end
