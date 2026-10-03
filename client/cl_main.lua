local globalState           = XTPrison.world
local prisonModules         = XTPrison.load 'modules.client.prison'
local prisonBreakModules    = XTPrison.load 'modules.client.prisonbreak'
local prisonBreakcfg        = XTPrison.load 'configs.prisonbreak'

local function runPrisonAction(action, value)
    local ok, result, reason = pcall(action, value)
    if not ok or result ~= true then
        FreezeEntityPosition(PlayerPedId(), false)
        DoScreenFadeIn(250)
        reason = ok and (reason or 'client_rejected') or tostring(result)
        XTPrison.log('error', 'Acao da prisao: ' .. tostring(reason))
        pr_lib.Notify({ title = 'XT Prison', description = locale('notify.action_failed'):format(tostring(reason)), type = 'error' })
        return false, reason
    end
    return true
end

pr_lib.callback.register('xt-prison:client:enterJail', function(value) return runPrisonAction(prisonModules.enterPrison, value) end)
pr_lib.callback.register('xt-prison:client:exitJail', function(value) return runPrisonAction(prisonModules.exitPrison, value) end)

-- Jail Player Input Menu --
pr_lib.callback.register('xt-prison:client:jailPlayerInput', function(nearbyPlayers)
    local rules = XTPrison.settings and XTPrison.settings.sentence or {}
    local input = pr_lib.InputDialog(locale('input.jail_player'), {
        { type = 'select', label = locale('input.playerid'), options = nearbyPlayers, icon = 'users', required = true },
        { type = 'number', label = 'Tempo de prisão', description = 'Quantidade da unidade selecionada', icon = 'hourglass', default = 1, min = 1, max = tonumber(rules.maxAmount) or 9999, required = true },
        { type = 'select', label = 'Unidade', default = rules.defaultUnit or 'minutes', required = true, options = {
            { label = 'Minutos', value = 'minutes' },
            { label = 'Horas', value = 'hours' },
            { label = 'Dias', value = 'days' },
        }},
        { type = 'select', label = 'Contagem', default = rules.defaultClock or 'real', required = true, options = {
            { label = 'Vida real', value = 'real' },
            { label = 'Tempo do jogo', value = 'game' },
        }},
    })
    if not input then return end

    return input
end)

-- Player Load --
local function playerLoaded()
    XTPrison.refreshCache()
    prisonModules.createPrisonZone()
    prisonBreakModules.createHackZones()
    if prisonBreakcfg and prisonBreakcfg.Escapes then
        prisonBreakModules.setEscapeAlarms(globalState and globalState.escapeAlarms or {})
    else
        prisonBreakModules.setPrisonAlarm(globalState and globalState.prisonAlarms or false)
    end

    Wait(500)

    local jailTime = pr_lib.callback.await('xt-prison:server:initJailTime', false)
    if jailTime and jailTime ~= 0 and jailTime > 0 then
        prisonModules.enterPrison(jailTime)
    end
end

-- Handlers --
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    playerLoaded()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    prisonModules.prisonCleanup()
end)

AddEventHandler('xt-prison:client:onLoad', function()
    playerLoaded()
end)

AddEventHandler('xt-prison:client:onUnload', function()
    prisonModules.prisonCleanup()
end)

AddEventHandler('xt-prison:client:configurationUpdated', function()
    prisonModules.removeCheckoutLocation()
    prisonModules.createCheckoutLocation()
    prisonBreakModules.setEscapeAlarms(globalState.escapeAlarms or {})
end)

AddEventHandler('xt-prison:client:alarmCacheChanged', function(value)
    if not prisonBreakcfg.Escapes then prisonBreakModules.setPrisonAlarm(value) end
end)

