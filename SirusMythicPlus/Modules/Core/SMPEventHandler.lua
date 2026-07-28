---@class SMPEventHandler
local SMPEventHandler = SMPLoader:CreateModule("SMPEventHandler")
local _EventHandler = SMPEventHandler.private

---@type SMPTaboo
local SMPTaboo = SMPLoader:ImportModule("SMPTaboo")

---@type SMPFrame
local SMPFrame = SMPLoader:ImportModule("SMPFrame")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

local MODIFIER_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
}

function _EventHandler:MythicPlusStatUpdate(_, success)
    if success and SMPTaboo:IsShown() then
        C_Timer:After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:ChallengeModeScoreUpdate()
    if SMPTaboo:IsShown() then
        C_Timer:After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:ChallengeModeMapsUpdate()
    if SMPTaboo:IsShown() then
        C_Timer:After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:LadderSearchResult(_, bracketType, searchText)
    SMPMessageBus.shared:Fire("LadderSearchResult", bracketType, searchText)
    if SMPTaboo:IsShown() then
        C_Timer:After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:ModifierStateChanged(_, key)
    if not MODIFIER_KEYS[key] then return end
    if not SMPTaboo:IsShown() then return end

    local owner = GameTooltip:GetOwner()
    local notOnAuras = not (owner and owner.UpdateTooltip)
    if notOnAuras and UnitExists("mouseover") then
        C_Timer:After(0, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function SMPEventHandler:RegisterEvents()
    local f = CreateFrame("Frame")

    if RegisterCustomEvent then
        RegisterCustomEvent(f, "MYTHIC_PLUS_PLAYER_STAT_UPDATE")
        RegisterCustomEvent(f, "CHALLENGE_MODE_SCORE_UPDATE")
        RegisterCustomEvent(f, "CHALLENGE_MODE_MAPS_UPDATE")
        RegisterCustomEvent(f, "LADDER_MYTHIC_PLUS_SEARCH_RESULT")
    end

    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("MYTHIC_PLUS_PLAYER_STAT_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_SCORE_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    f:RegisterEvent("LADDER_MYTHIC_PLUS_SEARCH_RESULT")
    f:RegisterEvent("MODIFIER_STATE_CHANGED")

    f:SetScript("OnEvent", function(_, event, ...)
        local args = ""
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            args = args .. tostring(v) .. (i < select("#", ...) and ", " or "")
        end
        SMPDebug:Log("WOW_EVENT", "[EventHandler] " .. event .. (args ~= "" and (" (" .. args .. ")") or ""))

        if event == "ADDON_LOADED" then
            local addonName = ...
            if addonName == "ElvUI" or (addonName and addonName:match("^SharedMedia")) then
                SMPFrame:InvalidateTextures()
            end
        elseif event == "MYTHIC_PLUS_PLAYER_STAT_UPDATE" then
            _EventHandler:MythicPlusStatUpdate(...)
        elseif event == "CHALLENGE_MODE_SCORE_UPDATE" then
            _EventHandler:ChallengeModeScoreUpdate()
        elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
            _EventHandler:ChallengeModeMapsUpdate()
        elseif event == "LADDER_MYTHIC_PLUS_SEARCH_RESULT" then
            _EventHandler:LadderSearchResult(...)
        elseif event == "MODIFIER_STATE_CHANGED" then
            _EventHandler:ModifierStateChanged(...)
        end
    end)
end
