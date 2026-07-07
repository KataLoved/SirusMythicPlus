---@class SMPEventHandler
local SMPEventHandler = SMPLoader:CreateModule("SMPEventHandler")
local _EventHandler = SMPEventHandler.private

---@type SMPTaboo
local SMPTaboo = SMPLoader:ImportModule("SMPTaboo")

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
        C_Timer.After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:ChallengeModeScoreUpdate()
    if SMPTaboo:IsShown() then
        C_Timer.After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:ChallengeModeMapsUpdate()
    if SMPTaboo:IsShown() then
        C_Timer.After(0.1, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function _EventHandler:LadderSearchResult(_, bracketType)
    if SMPTaboo:IsShown() then
        C_Timer.After(0.1, function()
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
        C_Timer.After(0, function()
            SMPTaboo:RefreshTooltip()
        end)
    end
end

function SMPEventHandler:RegisterEvents()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MYTHIC_PLUS_PLAYER_STAT_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_SCORE_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    f:RegisterEvent("LADDER_MYTHIC_PLUS_SEARCH_RESULT")
    f:RegisterEvent("MODIFIER_STATE_CHANGED")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "MYTHIC_PLUS_PLAYER_STAT_UPDATE" then
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
