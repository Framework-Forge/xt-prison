local function loaded()
    TriggerEvent('xt-prison:client:onLoad')
end

local function unloaded()
    TriggerEvent('xt-prison:client:onUnload')
end

AddEventHandler('pr_bridge:client:OnPlayerLoaded', loaded)
AddEventHandler('pr_bridge:client:OnPlayerUnloaded', unloaded)

RegisterNetEvent('xt-prison:client:notify', function(data)
    pr_lib.Notify(data)
end)
