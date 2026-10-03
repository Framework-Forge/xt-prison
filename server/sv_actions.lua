-- One server-side action contract for commands, roster and trusted integrations.
local function persist(src)
    return XTPrison.persistPlayer and XTPrison.persistPlayer(src) == true
end

function XTPrison.actionFailure(actor, target, action, reason)
    reason = tostring(reason or 'unknown')
    XTPrison.log('error', ('%s actor=%s target=%s: %s'):format(action, actor or '-', target or '-', reason))
    local data = { title = 'XT Prison', description = locale('notify.action_failed'):format(reason), type = 'error' }
    if actor and tonumber(actor) and tonumber(actor) > 0 then XTPrison.notifyPlayer(tonumber(actor), data) end
    if target and target ~= actor and getPlayer(target) then XTPrison.notifyPlayer(target, data) end
end

local function act(src, value, release)
    src = tonumber(src)
    local identifier = src and getCharID(src)
    if not identifier or not getPlayer(src) then return false, 'invalid_player' end
    local db = XTPrison.load('modules.server.db')
    local ready, err = db.awaitReady()
    if not ready then return false, err or 'database_unavailable' end
    if getCharID(src) ~= identifier then return false, 'player_changed' end
    local lock = 'xt-prison:action:' .. identifier
    if pr_lib.cache.get(lock) then return false, 'action_in_progress' end
    pr_lib.cache.set(lock, true)
    local state = XTPrison.playerState(src)
    local previous = { jailTime = state.jailTime, jailSentence = state.jailSentence }
    local previousJob = pr_lib.framework.GetPlayerJob(src)
    local function restore()
        -- Roll back by character identity, never by a potentially reused source.
        pr_lib.cache.set('xt-prison:character:' .. identifier, {
            jailTime = previous.jailTime, jailSentence = previous.jailSentence, xtprison_identifier = identifier,
        })
        pr_lib.database.insert(db.UPDATE_JAILTIME, {
            identifier, previous.jailTime, previous.jailSentence and json.encode(previous.jailSentence) or nil,
        })
        if getCharID(src) == identifier then
            setJailTime(src, previous.jailTime)
            XTPrison.playerState(src):set('jailSentence', previous.jailSentence)
            if previousJob and previousJob.name then
                local job = pr_lib.framework.GetPlayerJob(src)
                if job and job.name ~= previousJob.name then
                    local grade = previousJob.grade
                    setCharJob(src, previousJob.name, type(grade) == 'table' and grade.level or grade)
                end
            end
        end
    end
    local ok, success, reason = pcall(function()
        if getCharID(src) ~= identifier then return false, 'player_changed' end
        if release then
            if not setJailTime(src, 0) then return false, 'state_failed' end
        else
            local sentence = type(value) == 'table' and value or { amount = value }
            local amount = tonumber(sentence.amount)
            if not amount or amount ~= amount or amount <= 0 or amount == math.huge then return false, 'invalid_sentence' end
            if not setJailSentence(src, sentence) then return false, 'state_failed' end
        end
        if not persist(src) then return false, 'persistence_failed' end
        local name = release and 'xt-prison:client:exitJail' or 'xt-prison:client:enterJail'
        local argument = release and true or XTPrison.playerState(src).jailSentence
        local result, clientError = pr_lib.callback.awaitClient(src, name, 45000, argument)
        if result ~= true then return false, clientError or 'client_rejected' end
        if getCharID(src) ~= identifier then return false, 'player_changed' end
        return true
    end)
    if not ok or not success then
        local restored, restoreError = pcall(restore)
        if not restored then XTPrison.log('error', 'Rollback de prisao: ' .. tostring(restoreError)) end
    end
    pr_lib.cache.clear(lock)
    if not ok then return false, tostring(success) end
    return success == true, reason
end

function XTPrison.jailPlayer(src, sentence) return act(src, sentence, false) end
function XTPrison.releasePlayer(src) return act(src, nil, true) end

function XTPrison.prisonStatus(src)
    local state = XTPrison.playerState(src)
    if not state then return nil end
    local sentence = state.jailSentence
    local remaining = tonumber(state.jailTime) or 0
    if sentence and sentence.clock == 'real' and tonumber(sentence.endAt) then
        remaining = math.max(0, math.ceil((tonumber(sentence.endAt) - os.time()) / 60))
    elseif sentence and sentence.clock == 'game' and tonumber(sentence.nextTickAt) then
        local tick = math.max(1, tonumber(sentence.tickSeconds) or 2)
        if os.time() >= tonumber(sentence.nextTickAt) then
            remaining = math.max(0, remaining - math.floor((os.time() - tonumber(sentence.nextTickAt)) / tick) - 1)
        end
    end
    return { enabled = true, jailed = remaining > 0, remainingMinutes = remaining,
        sentence = sentence, clock = sentence and sentence.clock or 'real',
        maxAmount = (XTPrison.settings and XTPrison.settings.sentence or {}).maxAmount or 9999 }
end

pr_lib.addExports('JailPlayer', XTPrison.jailPlayer)
pr_lib.addExports('ReleasePlayer', XTPrison.releasePlayer)
pr_lib.addExports('GetPrisonStatus', XTPrison.prisonStatus)
