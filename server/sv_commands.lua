local config    = XTPrison.load 'configs.server'
local utils     = XTPrison.load 'modules.server.utils'

-- Check Jail Time --
pr_lib.addCommand('jailtime', {
    help = locale('commands.check_time'),
    params = {},
    restricted = false
}, function(source, args, raw)
    utils.checkJailTime(source)
end)

-- Jail Roster --
pr_lib.addCommand('prisoners', {
    help = locale('commands.prisoners_roster'),
    params = {},
    restricted = false
}, function(source, args, raw)
    if not utils.canManagePrison(source) then
        XTPrison.notifyPlayer(source, {
            title = locale('notify.no_access'),
            type = 'info'
        })
        return
    end

    local jailRoster = utils.generateJailRoster()

    TriggerClientEvent('xt-prison:client:openPrivateJailRoster', source, jailRoster)
end)


-- Jail/Unjail Player Commands --
if config.EnableJailCommand then
    pr_lib.addCommand('jail', {
        help = locale('commands.jail'),
        params = {},
        restricted = false
    }, function(source, args, _)
        if config.EnableJailCommand == false then
            return XTPrison.notifyPlayer(source, {
                title = 'XT Prison',
                description = 'O comando de prisão está desativado na configuração.',
                type = 'error'
            })
        end
        local player = getPlayer(source)
        if not player then return end

        if utils.canManagePrison(source) then
            local isAdmin = utils.isAdmin(source)
            local sourceCoords = GetEntityCoords(GetPlayerPed(source))
            local nearbyPlayers = {}
            for _, playerSource in ipairs(GetPlayers()) do
                playerSource = tonumber(playerSource)
                if playerSource and getPlayer(playerSource) and (playerSource ~= source or isAdmin)
                    and GetPlayerRoutingBucket(playerSource) == GetPlayerRoutingBucket(source) then
                    local playerPed = GetPlayerPed(playerSource)
                    local playerCoords = GetEntityCoords(playerPed)
                    local distance = #(sourceCoords - playerCoords)
                    if distance <= 5.0 then
                        nearbyPlayers[#nearbyPlayers + 1] = {
                            id = playerSource,
                            coords = playerCoords,
                            distance = distance,
                        }
                    end
                end
            end
            local formattedPlayers = {}

            for i = 1, #nearbyPlayers do
                local pid = nearbyPlayers[i].id

                formattedPlayers[#formattedPlayers + 1] = {
                    label = getCharName(pid) .. ' (' .. pid .. ')',
                    value = pid,
                    distance = nearbyPlayers[i].distance
                }
            end

            table.sort(formattedPlayers, function(a, b)
                return a.distance < b.distance
            end)

            local jailInput, inputError = pr_lib.callback.awaitClient(source, 'xt-prison:client:jailPlayerInput', 120000, formattedPlayers)
            if inputError then XTPrison.actionFailure(source, source, 'jail_input', inputError); return end
            if type(jailInput) ~= 'table' or not utils.canManagePrison(source) then return end

            local targetSource = tonumber(jailInput[1])
            if not targetSource or (targetSource == source and not utils.isAdmin(source)) then return end
            if GetPlayerRoutingBucket(targetSource) ~= GetPlayerRoutingBucket(source) then return end
            local sentence = {
                amount = tonumber(jailInput[2]),
                unit = jailInput[3],
                clock = jailInput[4],
            }
            local unitLabels = { minutes = 'minutos', hours = 'horas', days = 'dias' }
            local sentenceLabel = ('%s %s (%s)'):format(sentence.amount or 0, unitLabels[sentence.unit] or sentence.unit, sentence.clock == 'game' and 'tempo do jogo' or 'vida real')

            local targetPlayer = getPlayer(targetSource)
            if not targetPlayer then
                return XTPrison.notifyPlayer(source, {
                    title = locale('notify.invalid_player'),
                    type = 'error'
                })
            end

            local dist = utils.playerDistanceCheck(source, targetSource)
            if not dist then return end

            local notifyTitle = ('%s foi preso por %s'):format(getCharName(targetSource), sentenceLabel)
            local jailed, jailError = XTPrison.jailPlayer(targetSource, sentence)
            if not jailed then XTPrison.actionFailure(source, targetSource, 'jail', jailError); return end

            XTPrison.notifyPlayer(source, {
                title = notifyTitle,
                icon = 'fas fa-lock',
                type = 'success',
                duration = 5000
            })
        else
            XTPrison.notifyPlayer(source, {
                title = locale('notify.no_access'),
                type = 'info'
            })
        end
    end)

    pr_lib.addCommand('unjail', {
        help = locale('commands.unjail'),
        params = {{
            name = 'id',
            type = 'playerId',
            help = locale('commands.playerid')
        }}
    }, function(source, args)
        if not utils.canManagePrison(source) then return end

        local targetPlayer = getPlayer(args.id)
        if not targetPlayer then
            return XTPrison.notifyPlayer(source, {
                title = locale('notify.invalid_player'),
                type = 'error'
            })
        end

        local state = XTPrison.playerState(args.id)
        if state and state.jailTime <= 0 then
            return
        end

        local released, releaseError = XTPrison.releasePlayer(args.id)
        if not released then XTPrison.actionFailure(source, args.id, 'release', releaseError); return end
        if released then
            XTPrison.notifyPlayer(source, {
                title = (locale('notify.player_released')):format(getCharName(args.id)),
                icon = 'fas fa-lock',
                type = 'success',
                duration = 5000
            })
        end
    end)
end


