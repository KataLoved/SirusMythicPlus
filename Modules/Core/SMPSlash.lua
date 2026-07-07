---@class SMPSlash
local SMPSlash = SMPLoader:CreateModule("SMPSlash")

---@type SMPLib
local SMPLib = SMPLoader:ImportModule("SMPLib")

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
    SMP:Print("|cff00ff00/smp|r - открыть настройки")
    SMP:Print("|cff00ff00/smp version|r - версия аддона")
end
