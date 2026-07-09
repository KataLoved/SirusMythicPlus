---@class SMPMinimapButton
local SMPMinimapButton = SMPLoader:CreateModule("SMPMinimapButton")
local private = SMPMinimapButton.private

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

local LibDBIcon = LibStub("LibDBIcon-1.0")

private.dataObject = nil
private.db = {}

function SMPMinimapButton:Initialize()
    private.db = SMPConfig:GetGlobalConfig("minimap") or { hide = false }
    if private.db.minimapPos == nil then
        private.db.minimapPos = 225
    end

    private.dataObject = LibStub("LibDataBroker-1.1"):NewDataObject("SirusMythicPlus", {
        type = "launcher",
        label = "SirusMythicPlus",
        icon = "Interface\\AddOns\\SirusMythicPlus\\Media\\icon.tga",
        OnClick = function(_, button)
            if button == "LeftButton" then
                LibStub("AceConfigDialog-3.0"):Open("SirusMythicPlus")
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText("|cff00ff00Sirus|r|cffffffffMythicPlus|r", 1, 1, 1)
            tooltip:AddLine("ЛКМ — настройки", 0.9, 0.9, 0.9)
        end,
    })

    LibDBIcon:Register("SirusMythicPlus", private.dataObject, private.db)
end

function SMPMinimapButton:Show()
    private.db.hide = false
    SMPConfig:UpdateGlobalConfig("minimap", private.db)
    LibDBIcon:Show("SirusMythicPlus")
end

function SMPMinimapButton:Hide()
    private.db.hide = true
    SMPConfig:UpdateGlobalConfig("minimap", private.db)
    LibDBIcon:Hide("SirusMythicPlus")
end

---@return boolean
function SMPMinimapButton:IsHidden()
    return private.db.hide == true
end
