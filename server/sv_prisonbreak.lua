local globalState       = XTPrison.world
local prisonBreakcfg    = XTPrison.load 'configs.prisonbreak'
local prisonModules     = XTPrison.load 'modules.server.prisonbreak'

AddEventHandler('playerDropped',function()
    prisonModules.releasePlayerTerminals(source)
end)
AddEventHandler('pr_bridge:server:OnPlayerUnloaded',function(src)
    prisonModules.releasePlayerTerminals(src)
end)

-- Toggle Prison Alarms --
pr_lib.callback.register('xt-prison:server:setPrisonAlarms', function(src, setState, escapeId)
    if not XTPrison.load('modules.server.utils').isAdmin(src) then return false end
    return prisonModules.setEscapeAlarm(escapeId,setState)
end)

RegisterNetEvent('xt-prison:server:setPrisonAlarmsChance', function(success, terminalID)
    if type(success)~='boolean' or not prisonModules.ownsAttempt(source,terminalID) then return end
    local zone=prisonBreakcfg.HackZones[terminalID]
    local escape
    for _,entry in ipairs(prisonBreakcfg.Escapes or {}) do if entry.id==zone.escapeId then escape=entry;break end end
    if not escape then return end
    local alarmChance = success and escape.alarmSuccessChance or escape.alarmFailChance
    if math.random(100) > alarmChance then return end
    prisonModules.setEscapeAlarm(zone.escapeId,true)
end)

-- Prisonbreak Terminal States --
RegisterNetEvent('xt-prison:server:setTerminalHackedState', function(terminalID, setState)
    local src = source
    prisonModules.setTerminalHackedState(src, terminalID, setState)
end)

pr_lib.callback.register('xt-prison:server:setTerminalBusyState', function(source, terminalID, setState)
    return prisonModules.setTerminalBusyState(source, terminalID, setState)
end)
pr_lib.callback.register('xt-prison:server:completeTerminal',function(src,terminalID)
    local ok,reason=prisonModules.setTerminalHackedState(src,terminalID,true)
    if not ok then XTPrison.log('error',('Terminal %s, jogador %s: %s'):format(tostring(terminalID),tostring(src),reason or 'hack recusado')) end
    return ok==true,reason
end)

-- Remove Hacking Item(s) --
RegisterNetEvent('xt-prison:server:removePrisonbreakItems', function(success, terminalID)
    local src = source
    if type(success)~='boolean' or not prisonModules.ownsAttempt(src,terminalID) then return end

    local removeItemsChance = success and prisonBreakcfg.RemoveItemsChanceOnHack.success or prisonBreakcfg.RemoveItemsChanceOnHack.fail
    if math.random(100) > removeItemsChance then return end

    local zone=prisonBreakcfg.HackZones[terminalID]
    local requiredItems = zone.item and zone.item~='' and {[zone.item]=zone.itemCount or 1} or {}
    for requiredItem, requiredCount in pairs(requiredItems) do
        pr_lib.inventory.RemoveItem(src, requiredItem, requiredCount or 1)
    end
end)

-- Breakout of Prison --
pr_lib.callback.register('xt-prison:server:confirmBreakout', function(src)
    return prisonModules.prisonBreakout(src) == true
end)
RegisterNetEvent('xt-prison:server:triggerBreakout', function()
    local src = source
    prisonModules.prisonBreakout(src)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    globalState.prisonAlarms = false
    globalState.escapeAlarms = {}

    -- Reset Hack Zones & Doors --
    for x = 1, #prisonBreakcfg.HackZones do
        for _,gate in ipairs(prisonBreakcfg.HackZones[x].gates or {prisonBreakcfg.HackZones[x].gate}) do XTPrison.setGateState(gate, true) end

        globalState[('PrisonTerminal_%s'):format(x)] = nil
    end
end)

-- Create Hacking Terminals --
local function initializeTerminals()
    local key = 'xt-prison:configurationRevision'
    pr_lib.cache.set(key, (pr_lib.cache.get(key) or 0) + 1)
    globalState.escapeAlarms={};globalState.prisonAlarms=false
    for name, terminal in pairs(pr_lib.cache.get('xt-prison:world') or {}) do
        if name:match('^PrisonTerminal_') then
            for _,gate in ipairs(terminal.gates or {terminal.gate}) do XTPrison.setGateState(gate, true) end
            globalState[name] = nil
        end
    end
    for x = 1, #prisonBreakcfg.HackZones do
        globalState[('PrisonTerminal_%s'):format(x)] = {
            isHacked = false,
            isBusy = false,
            gate = prisonBreakcfg.HackZones[x].gate,
            gates = prisonBreakcfg.HackZones[x].gates,
            escapeId = prisonBreakcfg.HackZones[x].escapeId,
        }
    end
end

AddEventHandler('xt-prison:server:configurationUpdated', initializeTerminals)
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    initializeTerminals()
end)

