---@class SMPRequest
local SMPRequest = SMPLoader:CreateModule("SMPRequest")
local private = SMPRequest.private

---@type SMPDebug
local SMPDebug = SMPLoader:ImportModule("SMPDebug")

local MYTHIC_PLUS_BRACKET = (Enum and Enum.LadderBracketType and Enum.LadderBracketType.MYTHIC_PLUS) or 9

local STATE = {
    UNAVAILABLE = "unavailable",
    IDLE        = "idle",
    PENDING     = "pending",
    READY       = "ready",
    EMPTY       = "empty",
    NOT_FOUND   = "notfound",
    TIMEOUT     = "timeout",
    INVALID     = "invalid",
    THROTTLED   = "throttled",
}
SMPRequest.State = STATE

local REQUEST_TIMEOUT    = 10
local READY_TTL          = 290
local EMPTY_COOLDOWN     = 120
local NOT_FOUND_COOLDOWN = 300
local INVALID_COOLDOWN   = 600
local UNAVAILABLE_COOLDOWN = 60
local DEFAULT_DELAY      = 30
local RETRY_BACKOFF      = { 5, 10, 20, 45, 60 }
local WATCHDOG_INTERVAL  = 1

local COOLDOWNS = {
    [STATE.READY]       = READY_TTL,
    [STATE.EMPTY]       = EMPTY_COOLDOWN,
    [STATE.NOT_FOUND]   = NOT_FOUND_COOLDOWN,
    [STATE.INVALID]     = INVALID_COOLDOWN,
    [STATE.UNAVAILABLE] = UNAVAILABLE_COOLDOWN,
}

---@type table<string, table>
private.entries = {}
---@type table<string, table> lowercase имя -> {rank, name, classID, score, at}
private.ladderPlayers = {}
---@type table<string, table> lowercase текст поиска -> {names = {lowercase имена}, at}
private.ladderSearches = {}
---@type table<string, table|false> lowercase имя -> снапшот статистики или false («посчитано, данных нет»)
private.statCache = {}
private.localCache = nil

private.statInFlight = nil
private.statQueue = nil
private.searchInFlight = nil
private.searchQueue = nil
private.ladderBlockedUntil = 0
private.ladderSafe = true

private.listeners = {}
private.notifyScheduled = false
private.dispatching = false
private.watchdog = nil

private.counters = { sent = 0, suppressed = 0, timedOut = 0, throttled = 0 }

local function now()
    return GetTime()
end

local function log(message)
    SMPDebug:Log("REQUEST", message)
end

---@param s string
---@return number
local function utf8Len(s)
    if utf8 and utf8.len then
        local ok, n = pcall(utf8.len, s)
        if ok and n then return n end
    end
    if strlenutf8 then
        local ok, n = pcall(strlenutf8, s)
        if ok and n then return n end
    end
    return #s
end

---@param s string
---@return string
local function lowerStr(s)
    if utf8 and utf8.lower then
        local ok, v = pcall(utf8.lower, s)
        if ok and v then return v end
    end
    return string.lower(s)
end

---@param name string|nil
---@return string|nil
local function normalizeName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function statKey(lower) return "stat:" .. lower end
local function searchKey(lower) return "search:" .. lower end
local function ratingKey(guid) return "rating:" .. guid end
local MAPINFO_KEY = "mapinfo"

---@param key string
---@param kind string
---@param name string|nil
---@return table
local function getEntry(key, kind, name)
    local entry = private.entries[key]
    if not entry then
        entry = { key = key, kind = kind, state = STATE.IDLE, attempts = 0 }
        private.entries[key] = entry
    end
    if name then entry.name = name end
    return entry
end

---@param entry table
---@param state string
---@param cooldown number|nil
local function setState(entry, state, cooldown)
    local t = now()
    entry.state = state
    entry.updatedAt = t

    if state == STATE.PENDING then
        entry.sentAt = t
        entry.retryAt = nil
    elseif state == STATE.TIMEOUT then
        entry.attempts = (entry.attempts or 0) + 1
        local step = RETRY_BACKOFF[math.min(entry.attempts, #RETRY_BACKOFF)]
        entry.retryAt = t + (cooldown or step)
    else
        if state == STATE.READY then entry.attempts = 0 end
        entry.retryAt = t + (cooldown or COOLDOWNS[state] or 0)
    end
end

---@param entry table
---@return boolean
local function isBlocked(entry)
    if entry.state == STATE.PENDING then return true end
    if entry.retryAt and now() < entry.retryAt then return true end
    return false
end

function private.notify()
    if private.notifyScheduled then return end
    private.notifyScheduled = true

    C_Timer:After(0, function()
        private.notifyScheduled = false
        if private.dispatching then return end

        private.dispatching = true
        local listeners = private.listeners
        for i = 1, #listeners do
            local ok, err = pcall(listeners[i])
            if not ok then
                SMPDebug:Log("ERROR", "[SMPRequest] listener error: " .. tostring(err))
            end
        end
        private.dispatching = false
    end)
end

---@param callback function
function SMPRequest:Subscribe(callback)
    if type(callback) ~= "function" then
        error("SMPRequest:Subscribe: callback must be a function", 2)
    end
    local listeners = private.listeners
    for i = 1, #listeners do
        if listeners[i] == callback then return callback end
    end
    listeners[#listeners + 1] = callback
    return callback
end

---@param callback function
function SMPRequest:Unsubscribe(callback)
    local listeners = private.listeners
    for i = #listeners, 1, -1 do
        if listeners[i] == callback then table.remove(listeners, i) end
    end
end

function private.ensureWatchdog()
    if private.watchdog then return end
    private.watchdog = C_Timer:NewTicker(WATCHDOG_INTERVAL, function()
        private.tick()
    end)
end

function private.stopWatchdog()
    if private.watchdog then
        private.watchdog:Cancel()
        private.watchdog = nil
    end
end

---@return boolean
function private.hasPending()
    for _, entry in pairs(private.entries) do
        if entry.state == STATE.PENDING then return true end
    end
    return false
end

function private.maybeStopWatchdog()
    if not private.hasPending() then private.stopWatchdog() end
end

function private.tick()
    local t = now()
    local changed = false

    for _, entry in pairs(private.entries) do
        if entry.state == STATE.PENDING and entry.sentAt and (t - entry.sentAt) > REQUEST_TIMEOUT then
            setState(entry, STATE.TIMEOUT)
            private.counters.timedOut = private.counters.timedOut + 1
            changed = true
            log("timeout: " .. entry.key .. " (retry in " .. string.format("%.0f", (entry.retryAt or t) - t) .. "s)")

            if entry.kind == "stat" and private.statInFlight and statKey(private.statInFlight) == entry.key then
                private.statInFlight = nil
            elseif entry.kind == "search" and private.searchInFlight and searchKey(private.searchInFlight) == entry.key then
                private.searchInFlight = nil
            end
            entry.queued = nil
        end
    end

    if changed then
        private.pumpStatQueue()
        private.pumpSearchQueue()
        private.notify()
    end

    private.maybeStopWatchdog()
end

---@return boolean
function private.hasMapTable()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return false end
    local maps = C_ChallengeMode.GetMapTable()
    return maps ~= nil and #maps > 0
end

---@param dungeons table
local function sortDungeons(dungeons)
    table.sort(dungeons, function(a, b)
        if a.level == b.level then return a.name < b.name end
        return a.level > b.level
    end)
end

---@param playerName string
---@return table|nil
function private.readPlayerStats(playerName)
    if not (C_MythicPlus and C_MythicPlus.GetPlayerStatsForMap) then return nil end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo) then return nil end

    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then return nil end

    local dungeons = {}
    local bestLevel, bestDungeon, timed, count = 0, nil, 0, 0

    for i = 1, #maps do
        local mapID = maps[i]
        local mapName, _, timer = C_ChallengeMode.GetMapUIInfo(mapID)

        local ok, statInfo = pcall(C_MythicPlus.GetPlayerStatsForMap, playerName, mapID)
        if not ok then statInfo = nil end

        local level = (statInfo and statInfo.level) or 0
        local duration = (statInfo and statInfo.durationSec) or 0
        timer = timer or 0
        local inTime = level > 0 and duration > 0 and timer > 0 and duration <= timer

        if level > 0 then
            count = count + 1
            if inTime then timed = timed + 1 end
            if level > bestLevel then
                bestLevel = level
                bestDungeon = mapName
            end
        end

        dungeons[#dungeons + 1] = {
            mapID = mapID,
            name = mapName or "?",
            level = level,
            duration = duration,
            timer = timer,
            timed = inTime,
        }
    end

    sortDungeons(dungeons)

    return {
        dungeons = dungeons,
        bestLevel = (bestLevel > 0) and bestLevel or nil,
        bestDungeon = bestDungeon,
        timed = timed,
        total = count,
        count = count,
    }
end

---@return table|nil
function private.readLocalStats()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapScoreInfo) then return nil end

    local mapScoreInfo = C_ChallengeMode.GetMapScoreInfo()
    if not mapScoreInfo or #mapScoreInfo == 0 then return nil end

    local dungeons = {}
    local bestLevel, bestDungeon, timed, count = 0, nil, 0, 0

    for _, info in ipairs(mapScoreInfo) do
        local level = info.level or 0
        local duration, timer = 0, 0

        if level > 0 then
            if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
                local ok, inTimeInfo = pcall(C_MythicPlus.GetSeasonBestForMap, info.mapChallengeModeID)
                if ok and inTimeInfo then duration = inTimeInfo.durationSec or 0 end
            end
            local _, _, t = C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID)
            timer = t or 0

            count = count + 1
            if info.completedInTime == 1 then timed = timed + 1 end
            if level > bestLevel then
                bestLevel = level
                bestDungeon = info.name
            end
        end

        dungeons[#dungeons + 1] = {
            mapID = info.mapChallengeModeID,
            name = info.name or "?",
            level = level,
            duration = duration,
            timer = timer,
            timed = info.completedInTime == 1,
        }
    end

    sortDungeons(dungeons)

    return {
        dungeons = dungeons,
        bestLevel = (bestLevel > 0) and bestLevel or nil,
        bestDungeon = bestDungeon,
        timed = timed,
        total = count,
        count = count,
    }
end

---@param name string
---@param lower string
---@param force boolean|nil
---@return string state
function private.requestStat(name, lower, force)
    if not (C_MythicPlus and C_MythicPlus.RequestPlayerStat) then return STATE.UNAVAILABLE end

    local entry = getEntry(statKey(lower), "stat", name)

    local len = utf8Len(name)
    if len < 2 or len > 12 then
        setState(entry, STATE.INVALID)
        return entry.state
    end

    if not force and isBlocked(entry) then
        private.counters.suppressed = private.counters.suppressed + 1
        return entry.state
    end

    if private.statInFlight and private.statInFlight ~= lower then
        private.statQueue = { name = name, lower = lower }
        setState(entry, STATE.PENDING)
        entry.queued = true
        private.ensureWatchdog()
        return entry.state
    end

    entry.queued = nil
    private.statInFlight = lower
    setState(entry, STATE.PENDING)
    private.ensureWatchdog()
    private.counters.sent = private.counters.sent + 1
    log("RequestPlayerStat(" .. name .. ")")

    local ok, ret = pcall(C_MythicPlus.RequestPlayerStat, name)

    if not ok then
        private.statInFlight = nil
        setState(entry, STATE.UNAVAILABLE)
        SMPDebug:Log("ERROR", "[SMPRequest] RequestPlayerStat failed: " .. tostring(ret))
        return entry.state
    end

    if ret == false then
        private.statInFlight = nil
        private.statQueue = { name = name, lower = lower }
        entry.queued = true
    elseif ret == nil then
        if entry.state == STATE.PENDING then
            private.resolveStat(lower, true)
        end
    end

    return entry.state
end

function private.pumpStatQueue()
    local queued = private.statQueue
    if not queued then return end
    if private.statInFlight then return end

    private.statQueue = nil

    local entry = private.entries[statKey(queued.lower)]
    if entry then
        entry.state = STATE.IDLE
        entry.retryAt = nil
    end
    private.requestStat(queued.name, queued.lower, true)
end

---@param lower string
---@param success boolean
function private.resolveStat(lower, success)
    if private.statInFlight == lower then
        private.statInFlight = nil
    end

    private.statCache[lower] = nil

    local entry = private.entries[statKey(lower)]
    if entry then
        entry.queued = nil
        if success then
            local snapshot = entry.name and private.readPlayerStats(entry.name) or nil
            private.statCache[lower] = snapshot or false
            if snapshot and snapshot.count > 0 then
                setState(entry, STATE.READY)
            else
                setState(entry, STATE.EMPTY)
            end
        else
            setState(entry, STATE.NOT_FOUND)
        end
        log("stat resolved: " .. lower .. " -> " .. entry.state)
    end

    private.pumpStatQueue()
    private.maybeStopWatchdog()
    private.notify()
end

---@param searchLower string|nil
---@return number harvested
function private.harvestSearchResults(searchLower)
    if not (C_Ladder and C_Ladder.GetNumSearchResults and C_Ladder.GetSearchResultPlayerInfo) then return 0 end

    local ok, num = pcall(C_Ladder.GetNumSearchResults, MYTHIC_PLUS_BRACKET)
    if not ok or not num or num == 0 then return 0 end

    local names = {}
    local t = now()

    for i = 1, num do
        local infoOk, rank, name, _, classID, _, _, _, score = pcall(C_Ladder.GetSearchResultPlayerInfo, MYTHIC_PLUS_BRACKET, i)
        if infoOk and name then
            local lower = lowerStr(name)
            private.ladderPlayers[lower] = {
                rank = tonumber(rank),
                name = name,
                classID = tonumber(classID),
                score = tonumber(score) or 0,
                at = t,
            }
            names[#names + 1] = lower
        end
    end

    if searchLower then
        private.ladderSearches[searchLower] = { names = names, at = t }
    end

    return #names
end

---@param text string
---@param lower string
---@param force boolean|nil
---@return string state
function private.requestSearch(text, lower, force)
    if not private.ladderSafe then return STATE.UNAVAILABLE end
    if not (C_Ladder and C_Ladder.RequestSearch) then return STATE.UNAVAILABLE end

    local entry = getEntry(searchKey(lower), "search", text)

    if utf8Len(text) < 2 then
        setState(entry, STATE.INVALID)
        return entry.state
    end

    local t = now()
    if t < private.ladderBlockedUntil then
        setState(entry, STATE.THROTTLED, private.ladderBlockedUntil - t)
        private.counters.suppressed = private.counters.suppressed + 1
        return entry.state
    end

    if not force and isBlocked(entry) then
        private.counters.suppressed = private.counters.suppressed + 1
        return entry.state
    end

    if private.searchInFlight and private.searchInFlight ~= lower then
        private.searchQueue = { text = text, lower = lower }
        setState(entry, STATE.PENDING)
        entry.queued = true
        private.ensureWatchdog()
        return entry.state
    end

    entry.queued = nil
    private.searchInFlight = lower
    setState(entry, STATE.PENDING)
    private.ensureWatchdog()
    private.counters.sent = private.counters.sent + 1
    log("RequestSearch(" .. text .. ")")

    local ok, ret = pcall(C_Ladder.RequestSearch, MYTHIC_PLUS_BRACKET, text)

    if not ok then
        private.searchInFlight = nil
        private.ladderSafe = false
        setState(entry, STATE.UNAVAILABLE)
        SMPDebug:Log("ERROR", "[SMPRequest] RequestSearch failed: " .. tostring(ret))
    elseif ret == false then
        private.searchInFlight = nil
        setState(entry, STATE.INVALID)
    end

    return entry.state
end

function private.pumpSearchQueue()
    local queued = private.searchQueue
    if not queued then return end
    if private.searchInFlight then return end

    private.searchQueue = nil

    local entry = private.entries[searchKey(queued.lower)]
    if entry then
        entry.state = STATE.IDLE
        entry.retryAt = nil
    end
    private.requestSearch(queued.text, queued.lower, true)
end

---@param success boolean
function SMPRequest:HandleStatUpdate(success)
    local lower = private.statInFlight
    if not lower then
        private.pumpStatQueue()
        private.notify()
        return
    end
    private.resolveStat(lower, success and true or false)
end

---@param bracketType number|nil
---@param searchText string|nil
function SMPRequest:HandleSearchResult(bracketType, searchText)
    if bracketType and bracketType ~= MYTHIC_PLUS_BRACKET then return end

    local lower = searchText and lowerStr(searchText) or private.searchInFlight
    if private.searchInFlight then private.searchInFlight = nil end

    local harvested = private.harvestSearchResults(lower)

    if lower then
        local entry = private.entries[searchKey(lower)]
        if entry then
            entry.queued = nil
            setState(entry, harvested > 0 and STATE.READY or STATE.EMPTY)
        end
    end

    log("search resolved: " .. tostring(lower) .. " -> " .. harvested .. " результат(ов)")

    private.pumpSearchQueue()
    private.maybeStopWatchdog()
    private.notify()
end

---@param bracketType number|nil
---@param errorText string|nil
function SMPRequest:HandleSearchError(bracketType, errorText)
    if bracketType and bracketType ~= MYTHIC_PLUS_BRACKET then return end

    local lower = private.searchInFlight
    private.searchInFlight = nil

    if lower then
        local entry = private.entries[searchKey(lower)]
        if entry then
            entry.queued = nil
            setState(entry, STATE.INVALID)
            entry.errorText = errorText
        end
    end

    log("search error: " .. tostring(lower) .. " -> " .. tostring(errorText))

    private.pumpSearchQueue()
    private.maybeStopWatchdog()
    private.notify()
end

---@param bracketType number|nil
---@param delaySeconds number|nil
function SMPRequest:HandleSearchDelay(bracketType, delaySeconds)
    if bracketType and bracketType ~= MYTHIC_PLUS_BRACKET then return end

    local delay = tonumber(delaySeconds) or DEFAULT_DELAY
    private.ladderBlockedUntil = now() + delay
    private.counters.throttled = private.counters.throttled + 1

    local lower = private.searchInFlight
    private.searchInFlight = nil
    private.searchQueue = nil

    if lower then
        local entry = private.entries[searchKey(lower)]
        if entry then
            entry.queued = nil
            setState(entry, STATE.THROTTLED, delay)
        end
    end

    log("search throttled by server: " .. delay .. "s")

    private.maybeStopWatchdog()
    private.notify()
end

function SMPRequest:HandleMapsUpdate()
    private.localCache = nil
    local entry = private.entries[MAPINFO_KEY]
    if entry then setState(entry, STATE.READY) end
    private.maybeStopWatchdog()
    private.notify()
end

function SMPRequest:HandleScoreUpdate()
    private.localCache = nil
    private.notify()
end

---@param guid string|nil
function SMPRequest:HandleInspectItemLevel(guid)
    if not guid then return end

    local entry = private.entries[ratingKey(guid)]
    if entry then
        entry.queued = nil
        local rating = nil
        if entry.unit and UnitExists(entry.unit) and UnitGUID(entry.unit) == guid then
            rating = private.readRating(entry.unit)
        end
        setState(entry, rating and STATE.READY or STATE.EMPTY)
    end

    private.maybeStopWatchdog()
    private.notify()
end

---@param playerName string
---@return table|nil snapshot
---@return string state
function SMPRequest:GetPlayerStats(playerName)
    local name = normalizeName(playerName)
    if not name then return nil, STATE.INVALID end

    if not private.hasMapTable() then return nil, STATE.UNAVAILABLE end

    local lower = lowerStr(name)
    local cached = private.statCache[lower]
    if cached == nil then
        cached = private.readPlayerStats(name) or false
        private.statCache[lower] = cached
    end

    if cached and cached.count > 0 then
        local entry = getEntry(statKey(lower), "stat", name)
        if entry.state ~= STATE.PENDING and entry.state ~= STATE.READY then
            setState(entry, STATE.READY)
        end
        return cached, STATE.READY
    end

    return nil, private.requestStat(name, lower, false)
end

---@return table|nil snapshot
---@return string state
function SMPRequest:GetLocalStats()
    if private.localCache == nil then
        private.localCache = private.readLocalStats() or false
    end

    local snapshot = private.localCache or nil
    if snapshot and snapshot.count > 0 then
        return snapshot, STATE.READY
    end

    return snapshot or nil, self:RequestLocalMapStats()
end

---@return string state
function SMPRequest:RequestLocalMapStats()
    if not (C_MythicPlus and C_MythicPlus.RequestMapInfo) then return STATE.UNAVAILABLE end

    local entry = getEntry(MAPINFO_KEY, "mapinfo")
    if isBlocked(entry) then
        private.counters.suppressed = private.counters.suppressed + 1
        return entry.state
    end

    setState(entry, STATE.PENDING)
    private.ensureWatchdog()
    private.counters.sent = private.counters.sent + 1
    log("RequestMapInfo()")

    local ok, err = pcall(C_MythicPlus.RequestMapInfo)
    if not ok then
        setState(entry, STATE.UNAVAILABLE)
        SMPDebug:Log("ERROR", "[SMPRequest] RequestMapInfo failed: " .. tostring(err))
    end

    return entry.state
end

---@return number timed
---@return number total
function SMPRequest:GetLocalRunStats()
    if not (C_MythicPlus and C_MythicPlus.GetRunHistory) then return 0, 0 end

    local ok, runs = pcall(C_MythicPlus.GetRunHistory, true, true)
    if not ok or not runs then return 0, 0 end

    local timed = 0
    for _, run in ipairs(runs) do
        if run.completed then timed = timed + 1 end
    end
    return timed, #runs
end

---@param playerName string
---@param isLocal boolean|nil
---@return number|nil rank
---@return string state
---@return number|nil score
function SMPRequest:GetLadderRank(playerName, isLocal)
    if isLocal then
        if C_Ladder and C_Ladder.GetNumPersonalRecords and C_Ladder.GetPersonalRecordInfo then
            local ok, num = pcall(C_Ladder.GetNumPersonalRecords, MYTHIC_PLUS_BRACKET)
            if ok and num and num > 0 then
                local infoOk, rank, _, _, _, _, _, _, score = pcall(C_Ladder.GetPersonalRecordInfo, MYTHIC_PLUS_BRACKET, 1)
                if infoOk and rank then
                    return tonumber(rank), STATE.READY, tonumber(score)
                end
            end
        end
        return nil, STATE.EMPTY
    end

    local name = normalizeName(playerName)
    if not name then return nil, STATE.INVALID end

    local lower = lowerStr(name)
    local player = private.ladderPlayers[lower]
    if not player then
        private.harvestSearchResults(nil)
        player = private.ladderPlayers[lower]
    end

    if player then
        return player.rank, STATE.READY, player.score
    end

    return nil, private.requestSearch(name, lower, false)
end

---@param text string
---@return string state
function SMPRequest:StartSearch(text)
    local query = normalizeName(text)
    if not query then return STATE.INVALID end
    return private.requestSearch(query, lowerStr(query), true)
end

---@param text string
---@return table results
---@return string state
function SMPRequest:GetSearchResults(text)
    local query = normalizeName(text)
    if not query then return {}, STATE.INVALID end

    local lower = lowerStr(query)
    local entry = private.entries[searchKey(lower)]
    local state = entry and entry.state or STATE.IDLE

    local search = private.ladderSearches[lower]
    if not search then return {}, state end

    local results = {}
    for _, nameLower in ipairs(search.names) do
        local player = private.ladderPlayers[nameLower]
        if player then
            results[#results + 1] = {
                rank = player.rank,
                name = player.name,
                classID = player.classID,
                score = player.score or 0,
            }
        end
    end

    table.sort(results, function(a, b)
        return (a.rank or math.huge) < (b.rank or math.huge)
    end)

    return results, state
end

---@param unit string
---@return number|nil
function private.readRating(unit)
    if not (C_Inspect and C_Inspect.GetMythicRating) then return nil end
    local ok, rating = pcall(C_Inspect.GetMythicRating, unit)
    if ok then return rating end
    return nil
end

---@param unit string
---@return number|nil rating
---@return string state
function SMPRequest:GetMythicRating(unit)
    if not unit or not UnitExists(unit) then return nil, STATE.UNAVAILABLE end

    local guid = UnitGUID(unit)
    if not guid then return nil, STATE.UNAVAILABLE end

    local rating = private.readRating(unit)
    if rating then
        local entry = getEntry(ratingKey(guid), "rating")
        entry.unit = unit
        if entry.state ~= STATE.READY then setState(entry, STATE.READY) end
        return rating, STATE.READY
    end

    local entry = getEntry(ratingKey(guid), "rating")
    entry.unit = unit

    if isBlocked(entry) then return nil, entry.state end
    if not (C_Inspect and C_Inspect.RequestAvgItemLevel) then
        setState(entry, STATE.UNAVAILABLE)
        return nil, entry.state
    end

    local ok, sent = pcall(C_Inspect.RequestAvgItemLevel, unit)
    if not ok then
        setState(entry, STATE.UNAVAILABLE)
    elseif sent then
        setState(entry, STATE.PENDING)
        private.ensureWatchdog()
        private.counters.sent = private.counters.sent + 1
    else
        setState(entry, STATE.EMPTY, 15)
    end

    return nil, entry.state
end

---@return boolean
function SMPRequest:IsLadderAvailable()
    return private.ladderSafe and C_Ladder ~= nil and C_Ladder.RequestSearch ~= nil
end

---@param state string
---@return boolean
function SMPRequest:IsWaiting(state)
    return state == STATE.PENDING
end

---@param state string
---@return string|nil
function SMPRequest:GetStatusText(state)
    if state == STATE.PENDING then
        return "|cffffd100Загрузка...|r"
    elseif state == STATE.TIMEOUT then
        return "|cffff8000Сервер не отвечает|r"
    elseif state == STATE.THROTTLED then
        return "|cffff8000Сервер просит подождать|r"
    elseif state == STATE.NOT_FOUND then
        return "|cff808080Нет в базе|r"
    elseif state == STATE.EMPTY then
        return "|cff808080Нет данных|r"
    elseif state == STATE.UNAVAILABLE or state == STATE.INVALID then
        return "|cff808080-|r"
    end
    return nil
end

---@return table
function SMPRequest:GetCounters()
    return {
        sent = private.counters.sent,
        suppressed = private.counters.suppressed,
        timedOut = private.counters.timedOut,
        throttled = private.counters.throttled,
    }
end

function SMPRequest:Dump()
    local c = private.counters
    SMP:Print(("|cff00bfff[SMPRequest]|r отправлено: %d, подавлено дублей: %d, таймаутов: %d, троттлинга: %d")
        :format(c.sent, c.suppressed, c.timedOut, c.throttled))

    local t = now()
    local shown = 0
    for key, entry in pairs(private.entries) do
        local wait = entry.retryAt and math.max(0, entry.retryAt - t) or 0
        SMP:Print(("  %s = %s%s"):format(key, entry.state, wait > 0 and (" (ещё " .. string.format("%.0f", wait) .. "с)") or ""))
        shown = shown + 1
        if shown >= 25 then
            SMP:Print("  ...")
            break
        end
    end

    if private.ladderBlockedUntil > t then
        SMP:Print(("  ладдер заблокирован сервером ещё %.0fс"):format(private.ladderBlockedUntil - t))
    end
end

function SMPRequest:Reset()
    private.stopWatchdog()
    wipe(private.entries)
    wipe(private.ladderPlayers)
    wipe(private.ladderSearches)
    wipe(private.statCache)
    private.localCache = nil
    private.statInFlight = nil
    private.statQueue = nil
    private.searchInFlight = nil
    private.searchQueue = nil
    private.ladderBlockedUntil = 0
    private.ladderSafe = true
    private.counters = { sent = 0, suppressed = 0, timedOut = 0, throttled = 0 }
    private.notify()
end

function SMPRequest:Initialize()
	C_Timer:After(2, function()
        SMPRequest:RequestLocalMapStats()
    end)
end

return SMPRequest
