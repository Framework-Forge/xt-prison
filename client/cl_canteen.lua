local config = XTPrison.load 'configs.client'
local utils = XTPrison.load 'modules.client.utils'

local canteens = {}
local targetName = 'xt_prison_canteen'

local function onSelectCanteen(canteenInfo)
    if not pr_lib.progressCircle({
        label = 'Receiving Canteen Meal...',
        duration = canteenInfo.mealLength * 1000,
        position = 'bottom',
        useWhileDead = true,
        canCancel = false,
        disable = { move = true, car = true, combat = true, sprint = true },
    }) then return end

    if pr_lib.callback.await('xt-prison:server:receiveCanteenMeal', false) then
        pr_lib.Notify({
            title = 'Received Meal',
            description = 'You received a meal from the canteen!',
            type = 'success'
        })
    end
end

local function initCanteen()
    if next(canteens) then return end
    for index,canteenInfo in ipairs(config.CanteenPeds or {config.CanteenPed}) do
    local canteenPed = utils.createPed(canteenInfo.model, canteenInfo.coords, canteenInfo.scenario)
    local canteenBlip = utils.createBlip('Prison Canteen', canteenInfo.coords, 273, 0.3, 2)
    local name=targetName..'_'..index
    canteens[index]={ped=canteenPed,blip=canteenBlip,name=name}
    pr_lib.target.addLocalEntity(canteenPed, {{
        name = name,
        label = 'Receive Meal',
        icon = 'fas fa-utensils',
        onSelect = function() onSelectCanteen(canteenInfo) end
    }})
    end
end

local function removeCanteen()
    for _,entry in pairs(canteens) do
        if DoesEntityExist(entry.ped) then pr_lib.target.removeLocalEntity(entry.ped,entry.name);DeletePed(entry.ped) end
        if DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
    end
    canteens={}
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then initCanteen() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then removeCanteen() end
end)
AddEventHandler('xt-prison:client:onLoad', initCanteen)
AddEventHandler('xt-prison:client:onUnload', removeCanteen)
AddEventHandler('xt-prison:client:configurationUpdated', function()
    removeCanteen()
    initCanteen()
end)

