---@class SMPState
local SMPState = SMPLoader:CreateModule("SMPState")
local private = SMPState.private

---@class SMPChallengeState
local defaultState = {
    inChallenge = false,
    preStart = false,
    completed = false,
    completedOnTime = nil,
    timerStarted = false,
    demoModeActive = false,

    timer = 0,
    timeLimit = 0,
    timeLimitSilver = 0,
    timeLimitGold = 0,
    timeLimits = {},
    completionTimeMs = nil,

    deathCount = 0,
    deathTimeLost = 0,
    deathDetails = {},

    mapId = nil,
    level = 0,
    affixes = {},
    affixIds = {},

    forcesPercent = 0,
    forcesCompleted = false,
    forcesCompletionTime = nil,

    bosses = {},
    numBosses = 0,
    numBossesKilled = 0,

    currentPull = {},
    pullCount = 0,
    pullPercent = 0,

    splits = {},
    splitRecord = nil,
}

private.state = nil

function SMPState:Init()
    private.state = CopyTable(defaultState)
end

function SMPState:Reset()
    private.state = CopyTable(defaultState)
end

---@return SMPChallengeState
function SMPState:Get()
    if not private.state then
        self:Init()
    end
    return private.state
end

---@return number elapsed, number timeLimit
function SMPState:GetTimer()
    local s = private.state
    return s.timer, s.timeLimit
end

---@return number percent, boolean completed
function SMPState:GetForces()
    local s = private.state
    return s.forcesPercent, s.forcesCompleted
end

---@return table bosses, number killed, number total
function SMPState:GetBosses()
    local s = private.state
    return s.bosses, s.numBossesKilled, s.numBosses
end

---@return number count, number timeLost, table details
function SMPState:GetDeaths()
    local s = private.state
    return s.deathCount, s.deathTimeLost, s.deathDetails
end

---@return table affixes
function SMPState:GetAffixes()
    return private.state.affixes
end

---@return number level, number mapId
function SMPState:GetKeyInfo()
    local s = private.state
    return s.level, s.mapId
end
