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
---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

function SMP:OnInitialize()
    SMPConfig:Initialize()
    SMPEventHandler:RegisterEvents()
    SMPSlash:RegisterCommands()
    SMPTaboo:Initialize()
    SMPMinimapButton:Initialize()
    SMPPlayerSearch:Initialize()
    SMPFrame:Initialize()
    SMPCore:Initialize()
    SMPDebug:HookMessageBus(SMPMessageBus.shared)
end

function SMP:OnEnable()
end

function SMP:OnDisable()
end
