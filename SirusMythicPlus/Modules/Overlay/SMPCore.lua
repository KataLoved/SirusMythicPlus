---@class SMPCore
local SMPCore = SMPLoader:CreateModule("SMPCore")
local private = SMPCore.private

---@type SMPState
local SMPState = SMPLoader:ImportModule("SMPState")

---@type SMPMessageBus
local SMPMessageBus = SMPLoader:ImportModule("SMPMessageBus")

---@type SMPForcesData
local SMPForcesData = SMPLoader:ImportModule("SMPForcesData")

---@type SMPSplitsData
local SMPSplitsData = SMPLoader:ImportModule("SMPSplitsData")

---@type SMPConfig
local SMPConfig = SMPLoader:ImportModule("SMPConfig")

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

local TICK_INTERVAL = 0.1
local elapsed_acc = 0
local timerFrame = nil

local registeredEvents = {}
local eventFrame = nil  -- single shared frame for all events
SMPOverlayDB = SMPOverlayDB or {}

local SIRUS_CUSTOM_EVENTS = {
    MYTHIC_PLUS_PLAYER_STAT_UPDATE = true,
    CHALLENGE_MODE_SCORE_UPDATE = true,
    CHALLENGE_MODE_MAPS_UPDATE = true,
    LADDER_MYTHIC_PLUS_SEARCH_RESULT = true,
}

-- Challenge mode ID → area ID (for forces data lookup)
local CM_TO_AREA = {
    [4]  = 523,  -- Крепость Утгарда
    [5]  = 848,  -- Бастионы Адского Пламени
    [6]  = 838,  -- Узилище
    [8]  = 534,  -- Крепость Драк'Тарон
    [9]  = 525,  -- Чертоги Молний
    [10] = 835,  -- Кузня Крови
    [11] = 522,  -- Гробницы Маны
    [13] = 722,  -- Аукенайские гробницы
}

local pollTimer = nil
local POLL_INTERVAL = 2

function private:IsMythicDungeon()
    local _, instanceType, difficultyIndex = GetInstanceInfo()
    return instanceType == "party" and difficultyIndex == 3
end

function private:StartPolling()
    if pollTimer then return end
    SMPDebug:Log("POLL", "StartPolling: interval=" .. POLL_INTERVAL .. "s")
    pollTimer = C_Timer:NewTicker(POLL_INTERVAL, function()
        private:PollChallengeStatus()
    end)
end

function private:StopPolling()
    if pollTimer then
        pollTimer:Cancel()
        pollTimer = nil
        SMPDebug:Log("POLL", "StopPolling: timer cancelled")
    end
end

function private:PollChallengeStatus()
    if not private:IsMythicDungeon() then
        SMPDebug:Log("POLL", "PollChallengeStatus: not in mythic dungeon → stop polling")
        self:StopPolling()
        if SMPState:Get().inChallenge then
            self:StopChallenge()
        end
        return
    end

    local state = SMPState:Get()
    if state.inChallenge and not state.preStart then return end

    local active = C_ChallengeMode.IsChallengeModeActive()
    local mapId = C_ChallengeMode.GetActiveChallengeMapID()

    SMPDebug:Log("POLL", "PollChallengeStatus: active=" .. tostring(active) .. " mapId=" .. tostring(mapId))

    if active and mapId then
        SMPDebug:Log("POLL", "→ Key activated! mapId=" .. tostring(mapId) .. " → ActivateChallenge()")
        self:ActivateChallenge()
    end
end

function SMPCore:StopPolling()
    private:StopPolling()
    SMP:Print("|cff00ff00[POLL]|r Проверка остановлена по команде")
end

function SMPCore:ForceCheck()
    local inInstance = private:IsMythicDungeon()
    local _, instanceType, difficultyIndex = GetInstanceInfo()
    local active = C_ChallengeMode.IsChallengeModeActive()
    local mapId = C_ChallengeMode.GetActiveChallengeMapID()
    SMP:Print("|cffffff00[FORCE]|r inInstance=" .. tostring(inInstance) .. " type=" .. tostring(instanceType) .. " diff=" .. tostring(difficultyIndex))
    SMP:Print("|cffffff00[FORCE]|r active=" .. tostring(active) .. " mapId=" .. tostring(mapId))
    if mapId then
        SMP:Print("|cffffff00[FORCE]|r areaId=" .. tostring(CM_TO_AREA[mapId]) .. " (CM=" .. mapId .. ")")
    end
end

function private:SaveBossKillTimes(mapId, bosses)
    if not mapId then return end
    if not SMPOverlayDB[mapId] then
        SMPOverlayDB[mapId] = {}
    end
    for _, boss in ipairs(bosses) do
        if boss.killTime then
            SMPOverlayDB[mapId][boss.name] = boss.killTime
        end
    end
end

function private:LoadBossKillTimes(mapId)
    if not mapId or not SMPOverlayDB[mapId] then return {} end
    return SMPOverlayDB[mapId]
end

function private:ClearBossKillTimes(mapId)
    if mapId and SMPOverlayDB[mapId] then
        wipe(SMPOverlayDB[mapId])
    end
end

local function OnUpdate(_, elapsed)
    elapsed_acc = elapsed_acc + elapsed
    if elapsed_acc < TICK_INTERVAL then return end
    elapsed_acc = 0

    local state = SMPState:Get()
    if not state.inChallenge or state.completed or state.demoModeActive then return end
    if state.preStart then return end

    local _, timer = GetWorldElapsedTime(1)
    state.timer = timer
    SMPMessageBus.shared:Fire("TimerTick", state.timer, state.timeLimit)
end

function private:CheckChallenge()
    local inInstance = private:IsMythicDungeon()
    local active = C_ChallengeMode.IsChallengeModeActive()
    local activeMapId = C_ChallengeMode.GetActiveChallengeMapID()
    local state = SMPState:Get()

    SMPDebug:Log("STATE", "CheckChallenge: inInstance=" .. tostring(inInstance)
        .. " active=" .. tostring(active) .. " mapId=" .. tostring(activeMapId)
        .. " inChallenge=" .. tostring(state.inChallenge))

    if active and activeMapId then
        if not state.inChallenge then
            SMPDebug:Log("STATE", "→ Key already active, calling StartChallenge()")
            self:StartChallenge()
        else
            SMPDebug:Log("STATE", "→ Key active, already in challenge — skip")
        end
    elseif inInstance then
        if not state.inChallenge then
            SMPDebug:Log("STATE", "→ In mythic dungeon, key not started → ShowPreStartOverlay()")
            self:ShowPreStartOverlay()
        end
        self:StartPolling()
    else
        SMPDebug:Log("STATE", "→ Not in instance → stop polling + challenge")
        self:StopPolling()
        if state.inChallenge then
            self:StopChallenge()
        end
    end
end

function private:ShowPreStartOverlay()
    SMPDebug:Log("STATE", "ShowPreStartOverlay() called")

    SMPState:Reset()
    local state = SMPState:Get()

    state.inChallenge = true
    state.preStart = true
    state.timer = 0
    state.timerStarted = false

    self:UpdateBosses()

    elapsed_acc = 0
    if timerFrame then
        timerFrame:Show()
    end

    SMPMessageBus.shared:Fire("ChallengeStarted", state)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
end

function private:ActivateChallenge()
    local state = SMPState:Get()
    SMPDebug:Log("STATE", "ActivateChallenge() called, inChallenge=" .. tostring(state.inChallenge))
    if not state.inChallenge then return end

    state.mapId = C_ChallengeMode.GetActiveChallengeMapID()
    if not state.mapId then
        SMPDebug:Log("ERROR", "ActivateChallenge: GetActiveChallengeMapID() returned nil")
        return
    end

    state.preStart = false

    local level, affixIds = C_ChallengeMode.GetActiveKeystoneInfo()
    state.level = level or 0
    state.affixIds = affixIds or {}

    SMPDebug:Log("STATE", "ActivateChallenge: mapId=" .. tostring(state.mapId) .. " level=" .. tostring(state.level))

    wipe(state.affixes)
    for i, affixID in ipairs(state.affixIds) do
        local name, description = C_ChallengeMode.GetAffixInfo(affixID)
        state.affixes[i] = {
            id = affixID,
            name = name or ("Affix " .. affixID),
            description = description or "",
        }
    end

    local name, _, timeLimitBronze, timeLimitSilver, timeLimitGold = C_ChallengeMode.GetMapUIInfo(state.mapId)
    state.timeLimit = timeLimitBronze or 0
    state.timeLimitSilver = timeLimitSilver or 0
    state.timeLimitGold = timeLimitGold or 0

    state.timeLimits = {
        state.timeLimit,
        state.timeLimit * 0.8,
        state.timeLimit * 0.6,
    }

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    state.deathCount = deathCount or 0
    state.deathTimeLost = timeLost or 0

    state.forcesPercent = C_ChallengeMode.GetEnemyForcesProgress() or 0
    state.forcesCompleted = state.forcesPercent >= 100

    state.timerStarted = true
    self:UpdateBosses()

    if SMPConfig:GetProfileConfig("overlay.splitsEnabled") then
        local fallback = SMPConfig:GetProfileConfig("overlay.fallbackSplitBehavior") or "none"
        state.splitRecord = SMPSplitsData:GetBestWithFallback(state.mapId, state.level, fallback)
    end

    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)

    self:CheckPullTracking()
end

function private:StartChallenge()
    local state = SMPState:Get()
    SMPDebug:Log("STATE", "StartChallenge() called")

    SMPState:Reset()

    state.inChallenge = true
    state.preStart = false
    state.timerStarted = true
    state.mapId = C_ChallengeMode.GetActiveChallengeMapID()
    if not state.mapId then
        state.inChallenge = false
        SMPDebug:Log("ERROR", "StartChallenge: GetActiveChallengeMapID()=nil, abort")
        return
    end

    local level, affixIds = C_ChallengeMode.GetActiveKeystoneInfo()
    state.level = level or 0
    state.affixIds = affixIds or {}

    SMPDebug:Log("STATE", "StartChallenge: mapId=" .. tostring(state.mapId) .. " level=" .. tostring(state.level))

    wipe(state.affixes)
    for i, affixID in ipairs(state.affixIds) do
        local name, description = C_ChallengeMode.GetAffixInfo(affixID)
        state.affixes[i] = {
            id = affixID,
            name = name or ("Affix " .. affixID),
            description = description or "",
        }
    end

    local name, _, timeLimitBronze, timeLimitSilver, timeLimitGold = C_ChallengeMode.GetMapUIInfo(state.mapId)
    state.timeLimit = timeLimitBronze or 0
    state.timeLimitSilver = timeLimitSilver or 0
    state.timeLimitGold = timeLimitGold or 0

    state.timeLimits = {
        state.timeLimit,
        state.timeLimit * 0.8,
        state.timeLimit * 0.6,
    }

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    state.deathCount = deathCount or 0
    state.deathTimeLost = timeLost or 0

    state.forcesPercent = C_ChallengeMode.GetEnemyForcesProgress() or 0
    state.forcesCompleted = state.forcesPercent >= 100

    self:UpdateBosses()

    if SMPConfig:GetProfileConfig("overlay.splitsEnabled") then
        local fallback = SMPConfig:GetProfileConfig("overlay.fallbackSplitBehavior") or "none"
        state.splitRecord = SMPSplitsData:GetBestWithFallback(state.mapId, state.level, fallback)
    end

    elapsed_acc = 0
    if timerFrame then
        timerFrame:Show()
    end

    SMPMessageBus.shared:Fire("ChallengeStarted", state)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)

    self:CheckPullTracking()
end

function private:CompleteChallenge()
    local state = SMPState:Get()
    SMPDebug:Log("STATE", "CompleteChallenge() called, inChallenge=" .. tostring(state.inChallenge))
    if not state.inChallenge then return end

    state.completed = true

    local completionInfo = { C_ChallengeMode.GetCompletionInfo() }
    state.completionTimeMs = completionInfo[3]
    state.completedOnTime = completionInfo[4]

    SMPDebug:Log("STATE", "CompleteChallenge: time=" .. tostring(state.completionTimeMs) .. " onTime=" .. tostring(state.completedOnTime))

    state.forcesPercent = 100
    state.forcesCompleted = true
    if not state.forcesCompletionTime then
        state.forcesCompletionTime = state.timer
    end

    for _, boss in ipairs(state.bosses) do
        if boss.isDead and not boss.killTime then
            boss.killTime = state.timer
        end
    end

    self:SaveBossKillTimes(state.mapId, state.bosses)

    if SMPConfig:GetProfileConfig("overlay.splitsEnabled") then
        local bossTimes = {}
        for _, boss in ipairs(state.bosses) do
            if boss.killTime then
                bossTimes[boss.index] = boss.killTime
            end
        end
        SMPSplitsData:SaveRun(state.mapId, state.level, bossTimes, state.timer)
    end

    if timerFrame then
        timerFrame:Hide()
    end

    self:StopPullTracking()

    SMPMessageBus.shared:Fire("ChallengeCompleted", state)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
end

function private:StopChallenge()
    local state = SMPState:Get()
    SMPDebug:Log("STATE", "StopChallenge() called, inChallenge=" .. tostring(state.inChallenge) .. " demo=" .. tostring(state.demoModeActive))
    if not state.inChallenge and not state.demoModeActive then return end

    self:ClearBossKillTimes(state.mapId)
    self:StopPullTracking()

    if timerFrame then
        timerFrame:Hide()
    end

    SMPState:Reset()
    SMPMessageBus.shared:Fire("ChallengeStopped")
end

function private:UpdateDeaths()
    local state = SMPState:Get()
    if not state.inChallenge then return end

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    state.deathCount = deathCount or 0
    state.deathTimeLost = timeLost or 0

    SMPDebug:Log("STATE", "UpdateDeaths: count=" .. tostring(deathCount) .. " timeLost=" .. tostring(timeLost))

    SMPMessageBus.shared:Fire("DeathsUpdated", state.deathCount, state.deathTimeLost)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
end

function private:UpdateBosses()
    local state = SMPState:Get()
    if not state.inChallenge then return end

    local savedKills = self:LoadBossKillTimes(state.mapId)

    wipe(state.bosses)
    state.numBossesKilled = 0

    local numEncounters = C_InstanceEncounters.GetNumEncounters()
    state.numBosses = numEncounters

    SMPDebug:Log("STATE", "UpdateBosses: numEncounters=" .. tostring(numEncounters) .. " mapId=" .. tostring(state.mapId))

    for i = 1, numEncounters do
        local name, isDead = C_InstanceEncounters.GetEncounterInfo(i)
        if name then
            local bossIndex = #state.bosses + 1
            local killTime = nil

            if isDead then
                state.numBossesKilled = state.numBossesKilled + 1
                killTime = savedKills[name] or state.timer
            end

            local splitDiff = nil
            if isDead and state.splitRecord and state.splitRecord.bossTimes then
                local bestTime = state.splitRecord.bossTimes[i]
                if bestTime and killTime then
                    splitDiff = killTime - bestTime
                end
            end

            state.bosses[bossIndex] = {
                name = name,
                isDead = isDead,
                killTime = killTime,
                splitDiff = splitDiff,
                index = i,
            }

            state.splits[i] = {
                current = killTime,
                best = state.splitRecord and state.splitRecord.bossTimes and state.splitRecord.bossTimes[i],
                diff = splitDiff,
            }
        end
    end

    self:SaveBossKillTimes(state.mapId, state.bosses)

    SMPMessageBus.shared:Fire("BossesUpdated", state.bosses)
    SMPMessageBus.shared:Fire("SplitsUpdated", state.splits)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
end

function private:UpdateForces()
    local state = SMPState:Get()
    if not state.inChallenge then return end

    state.forcesPercent = C_ChallengeMode.GetEnemyForcesProgress() or 0
    state.forcesCompleted = state.forcesPercent >= 100

    SMPDebug:Log("STATE", "UpdateForces: percent=" .. string.format("%.2f", state.forcesPercent) .. " completed=" .. tostring(state.forcesCompleted))

    if state.forcesCompleted and not state.forcesCompletionTime then
        state.forcesCompletionTime = state.timer
    end

    SMPMessageBus.shared:Fire("ForcesUpdated", state.forcesPercent)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
end

function private:UpdateTimerState()
    local state = SMPState:Get()
    if not state.inChallenge then return end

    state.timerStarted = true
    SMPMessageBus.shared:Fire("TimerStarted")
end

local DEMO_BOSSES = {
    { name = "Test Boss 1" },
    { name = "Test Boss 2" },
    { name = "Test Boss 3" },
    { name = "Test Boss 4" },
    { name = "Test Boss 5" },
}

local DEMO_AFFIXES = {
    { id = 9,  name = "Аффикс 1", description = "Описание аффикса 1" },
    { id = 6,  name = "Аффикс 2", description = "Описание аффикса 2" },
    { id = 10, name = "Аффикс 3", description = "Описание аффикса 3" },
    { id = 12, name = "Аффикс 4", description = "Описание аффикса 4" },
}

local function randomInt(min, max)
    return math.random(min, max)
end

function SMPCore:EnableDemoMode()
    local state = SMPState:Get()

    local level = randomInt(5, 25)
    local timerSec = randomInt(300, 1800)
    local timeLimit = 2100

    state.inChallenge = true
    state.completed = false
    state.completedOnTime = nil
    state.timerStarted = true
    state.demoModeActive = true

    state.mapId = 524
    state.level = level

    local numAffixes = level >= 10 and 4 or (level >= 7 and 3 or (level >= 4 and 2 or 1))
    state.affixIds = {}
    state.affixes = {}
    for i = 1, numAffixes do
        state.affixIds[i] = DEMO_AFFIXES[i].id
        state.affixes[i] = { id = DEMO_AFFIXES[i].id, name = DEMO_AFFIXES[i].name, description = DEMO_AFFIXES[i].description }
    end

    state.timeLimit = timeLimit
    state.timeLimitSilver = math.floor(timeLimit * 0.8)
    state.timeLimitGold = math.floor(timeLimit * 0.6)
    state.timeLimits = { timeLimit, state.timeLimitSilver, state.timeLimitGold }

    state.timer = timerSec
    state.completionTimeMs = nil

    state.deathCount = randomInt(0, 8)
    state.deathTimeLost = state.deathCount * 5

    state.forcesPercent = randomInt(10, 95)
    state.forcesCompleted = false
    state.forcesCompletionTime = nil

    local totalForces = SMPForcesData:GetTotal(state.mapId) or 900
    local remainingPercent = 100 - state.forcesPercent

    if math.random() < 0.3 then
        state.pullCount = math.ceil((remainingPercent + randomInt(1, 5)) / 100 * totalForces)
    else
        state.pullCount = randomInt(5, 30)
    end
    state.pullPercent = state.pullCount / totalForces
    wipe(state.currentPull)

    wipe(state.bosses)
    local numKilled = randomInt(0, #DEMO_BOSSES)
    for i, demo in ipairs(DEMO_BOSSES) do
        local isDead = i <= numKilled
        state.bosses[i] = {
            name = demo.name,
            isDead = isDead,
            killTime = isDead and randomInt(120, timerSec) or nil,
            index = i,
        }
    end
    state.numBosses = #DEMO_BOSSES
    state.numBossesKilled = numKilled

    SMPMessageBus.shared:Fire("ChallengeStarted", state)
    SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
    SMPMessageBus.shared:Fire("PullUpdated", state.pullCount, state.pullPercent)
end

function SMPCore:DisableDemoMode()
    local state = SMPState:Get()
    state.demoModeActive = false
    SMPState:Reset()
    SMPMessageBus.shared:Fire("ChallengeStopped")
end

function SMPCore:IsDemoModeActive()
    local state = SMPState:Get()
    return state and state.demoModeActive or false
end

function SMPCore:Initialize()
    SMPState:Init()
    SMPDebug:Log("SYSTEM", "SMPCore:Initialize()")

    timerFrame = CreateFrame("Frame")
    timerFrame:Hide()
    timerFrame:SetScript("OnUpdate", OnUpdate)

    private:RegisterEvent("PLAYER_ENTERING_WORLD")
    private:RegisterEvent("CHALLENGE_MODE_START")
    private:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    private:RegisterEvent("CHALLENGE_MODE_CANCEL")
    private:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
    private:RegisterEvent("INSTANCE_ENCOUNTERS_UPDATE")
    private:RegisterEvent("WORLD_STATE_TIMER_START")
    private:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN")
    private:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    SMPMessageBus.shared:RegisterRepeating("ConfigChanged", function()
        SMPMessageBus.shared:Fire("OverlayConfigChanged")
        private:CheckPullTracking()
    end)

    private:CheckPullTracking()

    C_Timer:After(1, function()
        private:CheckChallenge()
    end)
end

function SMPCore:GetState()
    return SMPState:Get()
end

function SMPCore:IsActive()
    return SMPState:Get().inChallenge
end

function private:RegisterEvent(event)
    if registeredEvents[event] then return end
    registeredEvents[event] = true

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, evt, ...)
            private:OnEvent(evt, ...)
        end)
    end

    if SIRUS_CUSTOM_EVENTS[event] and RegisterCustomEvent then
        RegisterCustomEvent(eventFrame, event)
    end

    eventFrame:RegisterEvent(event)
end

function private:OnEvent(event, ...)
    local args = ""
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        args = args .. tostring(v) .. (i < select("#", ...) and ", " or "")
    end
    SMPDebug:Log("WOW_EVENT", event .. (args ~= "" and (" (" .. args .. ")") or ""))

    if event == "PLAYER_ENTERING_WORLD" then
        self:CheckChallenge()

    elseif event == "CHALLENGE_MODE_START" then
        self:ActivateChallenge()

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self:CompleteChallenge()

    elseif event == "CHALLENGE_MODE_CANCEL" then
        self:StopChallenge()
        self:StopPolling()

    elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        self:UpdateDeaths()

    elseif event == "INSTANCE_ENCOUNTERS_UPDATE" then
        self:UpdateBosses()
        self:UpdateForces()

    elseif event == "WORLD_STATE_TIMER_START" then
        self:UpdateTimerState()

    elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN" then
        self:TryAutoInsertKeystone()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:OnCombatLogEvent()

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        private:OnNameplateAdded(...)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        private:OnNameplateRemoved(...)
    end
end

local trackedPlates = {}
local pullTicker = nil
local PULL_TICK_INTERVAL = 0.25

function private:AreNewPlatesEnabled()
    return GetCVar("nameplateEnableNew") == "1"
end

function private:CheckPullTracking()
    local shouldTrack = self:AreNewPlatesEnabled()
        and SMPConfig:GetProfileConfig("overlay.showPullBar")
        and SMPState:Get().inChallenge

    if shouldTrack and not pullTicker then
        self:StartPullTracking()
    elseif not shouldTrack and pullTicker then
        self:StopPullTracking()
    end
end

function private:StartPullTracking()
    if pullTicker then return end

    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            if plate.namePlateUnitToken then
                self:OnNameplateAdded(plate.namePlateUnitToken)
            end
        end
    end

    pullTicker = C_Timer:NewTicker(PULL_TICK_INTERVAL, function()
        private:UpdatePullForces()
    end)

    SMPMessageBus.shared:Fire("PullTrackingStarted")
end

function private:StopPullTracking()
    if pullTicker then
        pullTicker:Cancel()
        pullTicker = nil
    end

    wipe(trackedPlates)

    local state = SMPState:Get()
    if state.pullCount ~= 0 or state.pullPercent ~= 0 then
        state.pullCount = 0
        state.pullPercent = 0
        wipe(state.currentPull)
        SMPMessageBus.shared:Fire("PullUpdated", 0, 0)
        SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
    end

    SMPMessageBus.shared:Fire("PullTrackingStopped")
end

function private:TryAutoInsertKeystone()
    SMPDebug:Log("STATE", "TryAutoInsertKeystone() called, enabled=" .. tostring(SMPConfig:GetProfileConfig("overlay.insertKeystoneAutomatically")))

    if not SMPConfig:GetProfileConfig("overlay.insertKeystoneAutomatically") then
        SMPDebug:Log("STATE", "→ Auto-insert disabled in config, skip")
        return
    end

    if C_ChallengeMode.SlotKeystone then
        local ok = pcall(C_ChallengeMode.SlotKeystone)
        SMPDebug:Log("STATE", "→ SlotKeystone() pcall result=" .. tostring(ok))
        if ok then return end
    end
    local GetContainerNumSlotsFn = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local GetContainerItemIDFn = C_Container and C_Container.GetContainerItemID or GetContainerItemID
    local GetContainerItemLinkFn = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    local UseContainerItemFn = C_Container and C_Container.UseContainerItem or UseContainerItem

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlotsFn(bag)
        for slot = 1, numSlots do
            local link = GetContainerItemLinkFn(bag, slot)
            if link and link:find("Keystone") then
                UseContainerItemFn(bag, slot)
                return
            end
        end
    end
end

function private:OnCombatLogEvent()
    local state = SMPState:Get()
    if not state.inChallenge or state.preStart then return end

    local _, subevent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()

    if subevent == "UNIT_DIED" and destName then
        SMPDebug:Log("STATE", "UNIT_DIED: destName=" .. tostring(destName) .. " GUID=" .. tostring(destGUID))
        local isPartyMember = false
        if destGUID == UnitGUID("player") then
            isPartyMember = true
        else
            for i = 1, 4 do
                if destGUID == UnitGUID("party" .. i) then
                    isPartyMember = true
                    break
                end
            end
        end

        if isPartyMember then
            if not state.deathDetails[destName] then
                state.deathDetails[destName] = {
                    count = 0,
                    timestamps = {},
                }
            end

            local playerDeaths = state.deathDetails[destName]
            playerDeaths.count = playerDeaths.count + 1
            playerDeaths.timestamps[#playerDeaths.timestamps + 1] = state.timer

            SMPMessageBus.shared:Fire("DeathDetailUpdated", destName, playerDeaths)
        end
    end
end

function private:OnNameplateAdded(unit)
    if not unit then return end
    if not UnitCanAttack(unit, "player") then return end
    if UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit) then return end
    trackedPlates[unit] = true
end

function private:OnNameplateRemoved(unit)
    if not unit then return end
    trackedPlates[unit] = nil
end

function private:UpdatePullForces()
    local state = SMPState:Get()
    if not state.inChallenge or state.demoModeActive then return end

    local mapId = state.mapId
    if not mapId then return end

    local areaId = CM_TO_AREA[mapId] or mapId

    local pullCount = 0
    wipe(state.currentPull)

    local partyGUIDs = {}
    local numMembers = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, numMembers do
        local unit = "party" .. i
        if UnitExists(unit) then
            partyGUIDs[UnitGUID(unit)] = true
        end
    end
    partyGUIDs[UnitGUID("player")] = true

    for unit in pairs(trackedPlates) do
        if UnitExists(unit) then
            local targetGUID = UnitGUID(unit .. "target")
            if targetGUID and partyGUIDs[targetGUID] then
                local guid = UnitGUID(unit)
                if guid then
                    local npcID = select(6, strsplit("-", guid))
                    npcID = tonumber(npcID)
                    if npcID then
                        local count = SMPForcesData:GetCount(areaId, npcID)
                        if count > 0 then
                            state.currentPull[guid] = count
                            pullCount = pullCount + count
                        end
                    end
                end
            end
        else
            trackedPlates[unit] = nil
        end
    end

    local totalForces = SMPForcesData:GetTotal(areaId)
    local pullPercent = totalForces > 0 and (pullCount / totalForces) or 0

    if state.pullCount ~= pullCount or state.pullPercent ~= pullPercent then
        state.pullCount = pullCount
        state.pullPercent = pullPercent
        SMPMessageBus.shared:Fire("PullUpdated", pullCount, pullPercent)
        SMPMessageBus.shared:Fire("ChallengeStateChanged", state)
    end
end

function SMPCore:IsPullTrackingActive()
    return pullTicker ~= nil
end

function SMPCore:RefreshPullTracking()
    private:CheckPullTracking()
end
