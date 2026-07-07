local ADDON_NAME, NS = ...

---@class SMP
SMP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0")

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")
---@type SMPEventHandler
local SMPEventHandler = SMPLoader:ImportModule("SMPEventHandler")
---@type SMPSlash
local SMPSlash = SMPLoader:ImportModule("SMPSlash")
---@type SMPTaboo
local SMPTaboo = SMPLoader:ImportModule("SMPTaboo")

function SMP:OnInitialize()
    SMPConfig:Initialize()
    SMPEventHandler:RegisterEvents()
    SMPSlash:RegisterCommands()
    SMPTaboo:Initialize()
end

function SMP:OnEnable()
end

function SMP:OnDisable()
end
