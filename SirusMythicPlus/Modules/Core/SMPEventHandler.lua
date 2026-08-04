---@class SMPEventHandler
local SMPEventHandler = SMPLoader:CreateModule("SMPEventHandler")
local _EventHandler = SMPEventHandler.private

---@type SMPTaboo
local SMPTaboo = SMPLoader:ImportModule("SMPTaboo")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

---@type SMPRequest
local SMPRequest = SMPLoader:ImportModule("SMPRequest")

local MODIFIER_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
}

local CUSTOM_EVENTS = {
    "MYTHIC_PLUS_PLAYER_STAT_UPDATE",
    "CHALLENGE_MODE_SCORE_UPDATE",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "LADDER_MYTHIC_PLUS_SEARCH_RESULT",
    "LADDER_MYTHIC_PLUS_SEARCH_ERROR",
    "LADDER_MYTHIC_PLUS_SEARCH_DELAY",
    "LADDER_MYTHIC_PLUS_PLAYER",
    "INSPECT_ITEM_LEVEL_UPDATE",
}

local WOW_EVENTS = {
    "ADDON_LOADED",
    "MODIFIER_STATE_CHANGED",
}

function _EventHandler:ModifierStateChanged(key)
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

    if f.RegisterCustomEvent then
        for _, event in ipairs(CUSTOM_EVENTS) do
            f:RegisterCustomEvent(event)
        end
    else
        SMPDebug:Log("ERROR", "[EventHandler] RegisterCustomEvent недоступен, M+ события не будут приходить")
    end

    for _, event in ipairs(WOW_EVENTS) do
        f:RegisterEvent(event)
    end

    f:SetScript("OnEvent", function(_, event, ...)
        if SMPDebug:IsEnabled() then
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring(select(i, ...))
            end
            local args = table.concat(parts, ", ")
            SMPDebug:Log("WOW_EVENT", "[EventHandler] " .. event .. (args ~= "" and (" (" .. args .. ")") or ""))
        end

        if event == "MYTHIC_PLUS_PLAYER_STAT_UPDATE" then
            local success = ...
            SMPRequest:HandleStatUpdate(success)
        elseif event == "CHALLENGE_MODE_SCORE_UPDATE" then
            SMPRequest:HandleScoreUpdate()
        elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
            SMPRequest:HandleMapsUpdate()
        elseif event == "LADDER_MYTHIC_PLUS_SEARCH_RESULT" then
            local bracketType, searchText = ...
            SMPMessageBus.shared:Fire("LadderSearchResult", bracketType, searchText)
            SMPRequest:HandleSearchResult(bracketType, searchText)
        elseif event == "LADDER_MYTHIC_PLUS_SEARCH_ERROR" then
            local bracketType, errorText = ...
            SMPRequest:HandleSearchError(bracketType, errorText)
        elseif event == "LADDER_MYTHIC_PLUS_SEARCH_DELAY" then
            local bracketType, delaySeconds = ...
            SMPRequest:HandleSearchDelay(bracketType, delaySeconds)
        elseif event == "LADDER_MYTHIC_PLUS_PLAYER" then
            SMPRequest:HandleScoreUpdate()
        elseif event == "INSPECT_ITEM_LEVEL_UPDATE" then
            local guid = ...
            SMPRequest:HandleInspectItemLevel(guid)
        elseif event == "MODIFIER_STATE_CHANGED" then
            local key = ...
            _EventHandler:ModifierStateChanged(key)
        end
    end)
end
