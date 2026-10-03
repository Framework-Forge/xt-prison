local config = XTPrison.load 'configs.client'
local utils = XTPrison.load 'modules.client.utils'

local doctors = {}
local targetName = 'xt_prison_infirmary'

local function receiveCheckup(docInfo)
    if not pr_lib.progressCircle({
        label = 'Receiving Checkup...',
        duration = docInfo.healLength * 1000,
        position = 'bottom',
        useWhileDead = true,
        canCancel = false,
        disable = { move = true, car = true, combat = true, sprint = true },
    }) then return end

    pr_lib.Notify({
        title = 'Healed',
        description = 'You received a checkup from the doctor!',
        type = 'success'
    })
    config.PlayerHealed()
end

local function initPrisonDoctor()
    if next(doctors) then return end
    for index,docInfo in ipairs(config.PrisonDoctors or {config.PrisonDoctor}) do
    local prisonDoc = utils.createPed(docInfo.model, docInfo.coords, docInfo.scenario)
    local prisonDocBlip = utils.createBlip('Prison Infirmary', docInfo.coords, 61, 0.3, 1)
    local name=targetName..'_'..index
    doctors[index]={ped=prisonDoc,blip=prisonDocBlip,name=name}
    pr_lib.target.addLocalEntity(prisonDoc, {{
        name = name,
        label = 'Receive Check-Up',
        icon = 'fas fa-stethoscope',
        onSelect = function() receiveCheckup(docInfo) end
    }})
    end
end

local function removePrisonDoctor()
    for _,entry in pairs(doctors) do
        if DoesEntityExist(entry.ped) then pr_lib.target.removeLocalEntity(entry.ped,entry.name);DeletePed(entry.ped) end
        if DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end
    end
    doctors={}
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then initPrisonDoctor() end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then removePrisonDoctor() end
end)
AddEventHandler('xt-prison:client:onLoad', initPrisonDoctor)
AddEventHandler('xt-prison:client:onUnload', removePrisonDoctor)
AddEventHandler('xt-prison:client:configurationUpdated', function()
    removePrisonDoctor()
    initPrisonDoctor()
end)

