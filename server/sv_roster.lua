local utils = XTPrison.load 'modules.server.utils'

-- View Jail Roster --
pr_lib.callback.register('xt-prison:server:getJailRoster', function(source)
    return utils.generateJailRoster()
end)

-- Unjails Player via Roster --
pr_lib.callback.register('xt-prison:server:unjailPlayerByRoster', function(source, targetSource)
    local isCop = utils.canManagePrison(source)
    if not isCop then return false end

    local state = XTPrison.playerState(targetSource)
    if state and state.jailTime > 0 then
        local released, reason = XTPrison.releasePlayer(targetSource)
        if not released then XTPrison.actionFailure(source, targetSource, 'release', reason); return false end

        XTPrison.notifyPlayer(targetSource, {
            title = locale('notify.freedom'),
            description = locale('notify.unjailed_by_roster')
        })
        return released
    end

    return state and (state.jailTime <= 0) or false
end)

-- Set Player Jail Time via Roster --
pr_lib.callback.register('xt-prison:server:changePlayerJailTimeByRoster', function(source, targetSource, newTime)
    local isCop = utils.canManagePrison(source)
    if not isCop then return false end

    local state = XTPrison.playerState(targetSource)
    if state and state.jailTime > 0 then
        local changed, reason = XTPrison.jailPlayer(targetSource, newTime)
        if not changed then XTPrison.actionFailure(source, targetSource, 'jail', reason); return false end
        local sentence = XTPrison.playerState(targetSource).jailSentence

        XTPrison.notifyPlayer(targetSource, {
            title = locale('notify.new_time_by_roster'),
            description = ('Nova pena: %s %s (%s)'):format(sentence.amount, sentence.unit, sentence.clock == 'game' and 'tempo do jogo' or 'vida real')
        })
        return true
    end

    return false
end)


