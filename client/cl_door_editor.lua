local provider
local warnedProvider=false
local function doorProvider()
    if provider then return provider end
    local ok,result=pcall(pr_lib.load,'@pr_bridge/bridge/doorlock/client')
    if ok and type(result)=='table' then provider=result;return provider end
    XTPrison.log('error','Adaptador doorlock client indisponível. Atualize/reinicie pr_bridge antes de xt-prison: '..tostring(result))
    if not warnedProvider then
        warnedProvider=true
        pr_lib.Notify({title='XT Prison',description='Atualize e reinicie pr_bridge antes de xt-prison para carregar o adaptador de portas.',type='error'})
    end
end
local active, previewPed, previewProp
local previewDoorHash
local function cleanup()
    if previewDoorHash then RemoveDoorFromSystem(previewDoorHash);previewDoorHash=nil end
    if previewProp and DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
    if previewPed and DoesEntityExist(previewPed) then DeleteEntity(previewPed) end
    previewPed,previewProp,active=nil,nil,false
end

function XTPrison.captureDoor(callback)
    if active then return false end
    local laser=pr_lib.devlaser or pr_lib.devLaser
    if not laser or not laser.start then return false end
    active=true
    pr_lib.ShowTextUI('[ENTER] Capturar porta fechada | [BACKSPACE] Cancelar')
    laser.start({distance=30,flags=-1,onStop=function()
        if active then active=false;pr_lib.HideTextUI();callback(nil) end
    end})
    CreateThread(function()
        while active do
            Wait(0)
            if IsControlJustReleased(0,201) or IsDisabledControlJustReleased(0,201) then
                local hit=laser.getTarget()
                local entity=hit and hit.entity
                if entity and DoesEntityExist(entity) and GetEntityType(entity)==3 then
                    local ok,result=pcall(function()
                        local c=GetEntityCoords(entity);local model=GetEntityModel(entity)
                        previewDoorHash=joaat('xt_prison_capture_'..entity..'_'..GetGameTimer())
                        AddDoorToSystem(previewDoorHash,model,c.x,c.y,c.z,false,false,false)
                        local deadline=GetGameTimer()+3000
                        while not DoorSystemGetIsPhysicsLoaded(previewDoorHash) and GetGameTimer()<deadline do Wait(0) end
                        assert(DoorSystemGetIsPhysicsLoaded(previewDoorHash),'A física da porta não carregou; captura cancelada.')
                        DoorSystemSetDoorState(previewDoorHash,1,false,true)
                        DoorSystemSetOpenRatio(previewDoorHash,0,false,true)
                        Wait(150)
                        c=GetEntityCoords(entity)
                        local r=GetEntityRotation(entity,2)
                        return {coords={x=c.x,y=c.y,z=c.z},rotation={x=r.x,y=r.y,z=r.z},heading=GetEntityHeading(entity),model=model}
                    end)
                    if previewDoorHash then RemoveDoorFromSystem(previewDoorHash);previewDoorHash=nil end
                    if not ok then pr_lib.Notify({description=tostring(result),type='error'});result=nil end
                    active=false;pr_lib.HideTextUI();laser.stop(true);callback(result)
                else pr_lib.Notify({description='Selecione o objeto da porta, não a parede.',type='error'}) end
            elseif IsControlJustReleased(0,177) or IsDisabledControlJustReleased(0,177) then
                active=false;pr_lib.HideTextUI();laser.stop(true);callback(nil)
            end
        end
    end)
    return true
end

function XTPrison.placeHackGizmo(zone,callback)
    if active then return false end
    local tools,gizmo=pr_lib.devtools,pr_lib.gizmo
    if not tools or not tools.placeAnimatedPed or not gizmo or not gizmo.start then return false end
    local drill=zone.game=='FleecaDrilling' or zone.game=='PlasmaDrilling'
    local animation=drill and {id='drill',label='Segurando perfuradora',animDict='anim@heists@fleeca_bank@drilling',animName='drill_straight_idle',flag=1}
        or {id='hack',label='Hack',animDict='amb@world_human_stand_mobile@male@text@base',animName='base',flag=1}
    active=true
    local started=tools.placeAnimatedPed(GetEntityModel(PlayerPedId()),1,{animation},function(result)
        if not result then cleanup();callback(nil);return end
        local p=result.coords or result.position or result
        local heading=tonumber(result.heading or result.w or (result.rotation and result.rotation.z) or p.w) or 0
        local ok,err=pcall(function()
            local model=GetEntityModel(PlayerPedId())
            pr_lib.requestModel(model)
            previewPed=CreatePed(4,model,p.x,p.y,p.z,heading,false,false)
            SetEntityCollision(previewPed,false,false);FreezeEntityPosition(previewPed,true);SetEntityInvincible(previewPed,true)
            pr_lib.requestAnimDict(animation.animDict)
            TaskPlayAnim(previewPed,animation.animDict,animation.animName,8,-8,-1,1,0,false,false,false)
            if drill then
                local prop=joaat('hei_prop_heist_drill');pr_lib.requestModel(prop)
                previewProp=CreateObjectNoOffset(prop,p.x,p.y,p.z,false,false,false)
                AttachEntityToEntity(previewProp,previewPed,GetPedBoneIndex(previewPed,28422),0,0,0,0,0,0,true,true,false,false,2,true)
            end
            local opened=gizmo.start(previewPed,nil,nil,{
                title='Posição exata do hack — ENTER salva, BACKSPACE cancela',
                onConfirm=function()
                    local c=GetEntityCoords(previewPed)
                    local final={x=c.x,y=c.y,z=c.z,w=GetEntityHeading(previewPed)}
                    cleanup();callback(final)
                end,
                onCancel=function() cleanup();callback(nil) end
            })
            if not opened then cleanup();callback(nil) end
        end)
        if not ok then cleanup();XTPrison.log('error',tostring(err));callback(nil) end
    end,{freezePlayer=true,preview=true,moveSpeed=0.6,heading=zone.animation and zone.animation.w or 0})
    if not started then cleanup() end
    return started
end

RegisterNetEvent('xt-prison:client:doorsRegistered',function(ids)
    if source==65535 and type(ids)=='table' then local api=doorProvider();if api then api.ensureRegistration(ids) end end
end)
local function refreshDoorRegistration()
    CreateThread(function()
        local status=pr_lib.callback.await('xt-prison:server:doorStatus',15000)
        local ids={};for _,id in pairs(type(status)=='table' and status or {}) do if id then ids[#ids+1]=id end end
        if #ids>0 then local api=doorProvider();if api then api.ensureRegistration(ids) end end
    end)
end
AddEventHandler('xt-prison:client:configurationUpdated',refreshDoorRegistration)
AddEventHandler('xt-prison:client:onLoad',refreshDoorRegistration)
AddEventHandler('onResourceStart',function(resource)
    if resource==GetCurrentResourceName() then SetTimeout(1500,refreshDoorRegistration) end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    if active and pr_lib.gizmo and pr_lib.gizmo.isActive() then pr_lib.gizmo.stop() end
    if active and pr_lib.devlaser then pr_lib.devlaser.stop(true) end
    cleanup();pr_lib.HideTextUI()
end)
