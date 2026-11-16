local provider = pr_lib.load('@pr_bridge/bridge/doorlock/server')
local config = XTPrison.load 'configs.prisonbreak'
local synchronizing = false

function XTPrison.setGateState(name, locked)
    local ok, reason = provider.setState(name, locked)
    if not ok then XTPrison.log('error', ('Door %s: %s'):format(tostring(name), reason or 'state_failed')) end
    return ok,reason
end

local function synchronize()
    if synchronizing or GetResourceState('ox_doorlock') ~= 'started' then return end
    synchronizing = true
    local seen = {}
    local ids, failures = {}, {}
    local names={}
    for _,escape in ipairs(config.Escapes or {}) do for _,gate in ipairs(escape.doors) do names[#names+1]=gate end end
    if not config.Escapes then for _,zone in ipairs(config.HackZones or {}) do names[#names+1]=zone.gate end end
    for _, gate in ipairs(names) do
        if not seen[gate] then
            seen[gate] = true
            local id, reason = provider.ensure(gate, (config.Doors or {})[gate], config.DoorGroup or 'forge-prison', {groups={police=1}})
            if id then
                ids[#ids+1]=id
                XTPrison.setGateState(gate, true)
            else
                failures[#failures+1]=gate..': '..tostring(reason)
                XTPrison.log('error', ('Door %s: %s. Capture a geometria da porta no ambiente de fuga.'):format(gate, reason or 'create_failed'))
            end
        end
    end
    synchronizing = false
    TriggerClientEvent('xt-prison:client:doorsRegistered',-1,ids)
    return {ids=ids,failures=failures}
end
XTPrison.synchronizeDoors=synchronize

pr_lib.callback.register('xt-prison:server:doorStatus',function()
    local result={}
    for _,zone in ipairs(config.HackZones or {}) do
        for _,gate in ipairs(zone.gates or {zone.gate}) do local door=provider.getByName(gate);result[gate]=door and door.id or false end
    end
    for _,escape in ipairs(config.Escapes or {}) do for _,gate in ipairs(escape.doors) do local door=provider.getByName(gate);result[gate]=door and door.id or false end end
    return result
end)
pr_lib.callback.register('xt-prison:server:doorCatalog',function(src)
    if not XTPrison.load('modules.server.utils').isAdmin(src) then return {} end
    local result={}
    for _,door in pairs(provider.catalog() or {}) do
        -- Never take over a housing/business door: only prison or unassigned groups.
        if door.name and (not door.doorGroup or door.doorGroup=='' or door.doorGroup==(config.DoorGroup or 'forge-prison')) then result[#result+1]={name=door.name,id=door.id} end
    end
    table.sort(result,function(a,b) return a.name<b.name end)
    return result
end)
pr_lib.callback.register('xt-prison:server:testAlarm',function(src,state,escapeId)
    if not XTPrison.load('modules.server.utils').isAdmin(src) or type(state)~='boolean' then return false end
    return XTPrison.load('modules.server.prisonbreak').setEscapeAlarm(escapeId,state)
end)

-- Wait for the provider's database load before looking up/creating persistent IDs.
AddEventHandler('ox_doorlock:loaded', synchronize)
AddEventHandler('xt-prison:server:configurationUpdated', synchronize)
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then CreateThread(function() Wait(1500); synchronize() end) end
end)
