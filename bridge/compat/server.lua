local utils         = XTPrison.load 'modules.server.utils'
local resources     = XTPrison.load 'bridge.compat.resources'

-- When setJailTime is called, compat for other resources is called
function syncJailCompatibility(src, time)
    if resources.randol_medical then
        exports.randol_medical:SetJailState(src, (time > 0))
    end

    -- Add other compat here (Medical, etc)
end

-- Compat for QB/QBX Prison Original Event --
RegisterNetEvent('prison:server:SetJailStatus', function(jailTime)
    local src = source
    setJailTime(src, ((jailTime < 0) and 0 or jailTime))
end)

-- Compat Event for QB Police Job --
RegisterNetEvent('police:server:JailPlayer', function(playerId, time)
    local src = source
    local dist = utils.playerDistanceCheck(src, playerId)
    if not dist then return end

    if not utils.isCop(src) then return end

    local jailed, reason = XTPrison.jailPlayer(playerId, time)
    if not jailed then XTPrison.actionFailure(src, playerId, 'jail', reason); return end
    if jailed then
        XTPrison.notifyPlayer(src, { title = ('Sent to Jail for %s minutes'):format(time), type = 'success' })
    end
end)


