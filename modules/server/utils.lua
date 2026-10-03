local config            = XTPrison.load 'configs.server'
local prisonBreakcfg    = XTPrison.load 'configs.prisonbreak'

local utils = {}

-- Check if Player is a Lifer --
function utils.liferCheck(source)
    local player = getPlayer(source)
    local playerState = XTPrison.playerState(source)
    local citizenid = getCharID(source)
    if not playerState then return false end
    local jailTime = playerState.jailTime
    local callback = false
    for x = 1, #config.Lifers do
        if config.Lifers[x] == citizenid then
            if jailTime ~= 999 then
                setJailTime(source, 999)
            end
            callback = true
            break
        end
    end
    return callback
end exports('isLifer', utils.liferCheck)

-- Check if Player is Cop --
function utils.isCop(source)
    local callback = false
    local type = type(config.PoliceJobs)
    if type == 'string' then
        return charHasJob(source, config.PoliceJobs)
    elseif type == 'table' then
        for x = 1, #config.PoliceJobs do
            if charHasJob(source, config.PoliceJobs[x]) then
                callback = true
                break
            end
        end
    end
    return callback
end

-- Distance Between 2 Players --
function utils.isAdmin(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    local ace = pr_lib.ace
    if ace and type(ace.isAdminWhitelisted) == 'function' and ace.isAdminWhitelisted(source) then return true end
    if ace and type(ace.isPlayerAceAllowed) == 'function' then
        for _, permission in ipairs({ 'xt-prison.admin', 'admin', 'group.admin', 'god' }) do
            if ace.isPlayerAceAllowed(source, permission) then return true end
        end
    end
    if type(pr_lib.framework.HasPermission) == 'function' then
        for _, permission in ipairs({ 'admin', 'god' }) do
            local ok, allowed = pcall(pr_lib.framework.HasPermission, source, permission)
            if ok and allowed == true then return true end
        end
    end
    return false
end

function utils.canManagePrison(source)
    return utils.isAdmin(source) or utils.isCop(source)
end

-- Distance Between 2 Players --
function utils.playerDistanceCheck(player1, player2)
    if player1 == player2 then return true end

    local playerPed = GetPlayerPed(player1)
    local targetPed = GetPlayerPed(player2)
    local playerCoords = GetEntityCoords(playerPed)
    local targetCoords = GetEntityCoords(targetPed)
    local dist = #(targetCoords - playerCoords)

    return (dist < 5)
end

-- Distance Between Player and Terminal --
function utils.terminalDistanceCheck(player1, terminal)
    if type(terminal) ~= 'number' or terminal % 1 ~= 0 or not prisonBreakcfg.HackZones[terminal] then return false end
    local playerPed = GetPlayerPed(player1)
    if playerPed == 0 then return false end
    local playerCoords = GetEntityCoords(playerPed)
    local zone = prisonBreakcfg.HackZones[terminal]
    if XTPrison.load('modules.break_settings').contains(zone,playerCoords) then return true end
    local animation=zone.animation
    if animation then
        local dx,dy,dz=playerCoords.x-animation.x,playerCoords.y-animation.y,playerCoords.z-animation.z
        return dx*dx+dy*dy+dz*dz<4
    end
    return false
end

function utils.checkJailTime(source)
    local player = getPlayer(source)
    local playerState = XTPrison.playerState(source)
    local isLifer = utils.liferCheck(source)
    if not playerState then return 0 end
    local jailTime

    if isLifer then
        XTPrison.notifyPlayer(source, {
            title = locale('notify.lifer'),
            icon = 'fas fa-lock',
            type = 'info'
        })
        return 999
    else
        jailTime = playerState.jailTime or 0
        if jailTime > 0 then
            XTPrison.notifyPlayer(source, {
                title = locale('notify.jail_time'),
                description = (locale('notify.time_left')):format(jailTime),
                icon = 'fas fa-hourglass',
                type = 'info'
            })
        elseif jailTime <= 0 then
            XTPrison.notifyPlayer(source, {
                title = locale('notify.jail_time'),
                description = locale('notify.no_time_left'),
                icon = 'fas fa-hourglass-end',
                type = 'info'
            })
        end
    end

    return jailTime
end

function utils.generateJailRoster()
    local roster = {}
    local players = GetPlayers()

    for _, src in pairs(players) do
        local state = XTPrison.playerState(tonumber(src))
        if state and state.jailTime > 0 then
            local charName = getCharName(tonumber(src))
            roster[#roster + 1] = {
                title = charName,
                description = (locale('notify.time_remaining')):format(state.jailTime),
                icon = 'fas fa-user-lock',
                private = {
                    source = tonumber(src),
                    name = charName,
                    jailTime = state.jailTime
                }
            }
        end
    end

    return roster
end

function utils.banPlayer(...)
    return config.banPlayer(...)
end

return utils


