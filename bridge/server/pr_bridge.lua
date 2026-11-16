local framework = pr_lib.framework

function getPlayer(source)
    return framework.GetPlayer(source)
end

function getCharID(source)
    return framework.GetIdentifier(source)
end

function getCharName(source)
    return framework.GetPlayerName(source) or ('Player %s'):format(source)
end

function charHasJob(source, job)
    if type(framework.PlayerHasJob) == 'function' then
        return framework.PlayerHasJob(source, job)
    end

    local playerJob = framework.GetPlayerJob(source)
    return playerJob and playerJob.name == job or false
end

function setCharJob(source, job, grade)
    local success, reason = framework.SetPlayerJob(source, job, tonumber(grade) or 0)
    local current = framework.GetPlayerJob(source)
    return success == true or (current and current.name == job) or false, reason
end

function setJailTime(source, time, status)
    local playerState = XTPrison.playerState(source)
    if not playerState or not getPlayer(source) then return false end

    time = tonumber(time)
    if not time or time ~= time or time == math.huge or time == -math.huge then return false end
    time = math.max(0, math.floor(time))
    status = status or (time > 0 and 'jailed' or 'free')
    if status ~= 'jailed' and status ~= 'fugitive' and status ~= 'free' then return false end
    if status == 'free' then time = 0 end
    playerState:set('prisonStatus', status, true)
    playerState:set('prisonLoaded', true, true)
    playerState:set('jailTime', time, true)
    playerState:set('xtprison_identifier', getCharID(source), true)
    if status == 'free' then playerState:set('jailSentence', nil, true) end

    if type(framework.SetPlayerMetadata) == 'function' then
        framework.SetPlayerMetadata(source, 'injail', status == 'jailed' and time or 0)
        framework.SetPlayerMetadata(source, 'prisonStatus', status)
    end

    syncJailCompatibility(source, status == 'jailed' and time or 0)
    return playerState.jailTime == time
end

local unitMinutes = { minutes = 1, hours = 60, days = 1440 }

function setJailSentence(source, sentence)
    sentence = type(sentence) == 'table' and sentence or { amount = sentence }
    local rules = XTPrison.settings and XTPrison.settings.sentence or {}
    local amount = math.max(0, math.floor(tonumber(sentence.amount) or 0))
    local maximum = math.max(1, math.floor(tonumber(rules.maxAmount) or 9999))
    amount = math.min(amount, maximum)

    local unit = unitMinutes[sentence.unit] and sentence.unit or rules.defaultUnit or 'minutes'
    local clock = sentence.clock == 'game' and 'game' or sentence.clock == 'real' and 'real' or rules.defaultClock or 'real'
    local minutes = amount * (unitMinutes[unit] or 1)
    local tickSeconds = clock == 'game' and math.max(1, tonumber(rules.gameMinuteSeconds) or 2) or 60
    local data = {
        amount = amount,
        unit = unit,
        clock = clock,
        totalMinutes = minutes,
        remainingMinutes = minutes,
        tickSeconds = tickSeconds,
        startedAt = os.time(),
        endAt = clock == 'real' and (os.time() + minutes * 60) or nil,
        nextTickAt = clock == 'game' and (os.time() + tickSeconds) or nil,
    }

    if not setJailTime(source, minutes) then return false end
    XTPrison.playerState(source):set('jailSentence', data, true)
    return data
end

exports('SetJailTime', setJailTime)
