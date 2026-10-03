local config            = XTPrison.load 'configs.client'
local prisonBreakcfg    = XTPrison.load 'configs.prisonbreak'
local utils             = XTPrison.load 'modules.client.utils'
local globalState       = XTPrison.world

local PrisonBreakBlip
local HackZones = {}
local activeAlarmNames = {}
local alarmRevision=0
local desiredAlarmNames={}
local hackSession
local emotes
local function hackTraceback(err)
    return debug.traceback(tostring(err), 2)
end
local function cleanupHack()
    if not hackSession then return end
    local session=hackSession;hackSession=nil
    local ok,err=pcall(emotes.finishSession,session)
    if not ok then XTPrison.log('error','Limpeza do hack: '..tostring(err)) end
    FreezeEntityPosition(session.ped,false)
    ClearPedTasks(session.ped)
end

local prisonBreakModules = {}

function prisonBreakModules.canHackTerminal(terminalID)
    local terminal = globalState[('PrisonTerminal_%s'):format(terminalID)]
    return terminal and not terminal.isHacked and not terminal.isBusy or false
end

-- Create Prisonbreak Hacking Zones --
function prisonBreakModules.createHackZones()
    if not XTPrison.settings then return false end
    if next(HackZones) then return true end
    local ok,err=pcall(function()
    for x = 1, #prisonBreakcfg.HackZones do
        local zoneInfo = prisonBreakcfg.HackZones[x]
        local definition = {
            name = ('xt_prison_hack_%s'):format(x),
            coords = zoneInfo.coords,
            radius = zoneInfo.radius,
            debug = config.DebugPoly,
            drawSprite = true,
            options = {{
                name = ('xt_prison_hack_option_%s'):format(x),
                label = locale('input.hack_gate'),
                icon = 'fas fa-laptop-code',
                items = zoneInfo.item and zoneInfo.item ~= '' and {[zoneInfo.item]=zoneInfo.itemCount or 1} or nil,
                onSelect = function() prisonBreakModules.startGateHack(x) end,
                canInteract = function()
                    local canHack = prisonBreakModules.canHackTerminal(x)
                    return (globalState.copCount or 0) >= prisonBreakcfg.MinimumPolice and canHack
                end
            }}
        }
        if zoneInfo.shape=='poly' then
            definition.points={}
            for _,point in ipairs(zoneInfo.points or {}) do definition.points[#definition.points+1]=vec3(point.x,point.y,zoneInfo.coords.z) end
            definition.thickness=zoneInfo.thickness
            HackZones[x]=pr_lib.target.addPolyZone(definition)
        else
            HackZones[x]=pr_lib.target.addSphereZone(definition)
        end
        assert(HackZones[x]~=nil and HackZones[x]~=false,'Target não registrou o terminal '..x)
    end
    end)
    if not ok then
        prisonBreakModules.removeHackZones()
        XTPrison.log('error','Registro de targets: '..tostring(err))
        return false
    end
    return true
end

function prisonBreakModules.removeBlip()
    if DoesBlipExist(PrisonBreakBlip) then
        RemoveBlip(PrisonBreakBlip)
    end
end

function prisonBreakModules.removeHackZones()
    for x,id in pairs(HackZones) do
        local ok,err=pcall(pr_lib.target.removeZone,id)
        if not ok then XTPrison.log('error','Remoção de target: '..tostring(err)) end
        HackZones[x] = nil
    end
end

function prisonBreakModules.startGateHack(ID)
    if hackSession then return end
    local zone=prisonBreakcfg.HackZones[ID]
    if not zone then return end
    local drilling=zone.game=='PlasmaDrilling' or zone.game=='FleecaDrilling'
    if drilling and not zone.animation then
        pr_lib.Notify({title='XT Prison',description='Configure the drilling ped position first.',type='error'})
        return
    end
    local setBusy,reason = pr_lib.callback.await('xt-prison:server:setTerminalBusyState',15000, ID, true)
    if not setBusy then
        ClearPedTasks(PlayerPedId())
        pr_lib.Notify({title='XT Prison',description=reason or 'Terminal ocupado, em cooldown ou sem os requisitos necessários.',type='error'})
        return
    end
    local setupOk,setupError=pcall(function()
        emotes=emotes or pr_lib.load('@pr_bridge/bridge/emotes/client')
        hackSession=emotes.beginSession({'prop_cs_tablet','hei_prop_heist_drill'})
    end)
    if not setupOk then
        XTPrison.log('error',tostring(setupError))
        pr_lib.callback.await('xt-prison:server:setTerminalBusyState',15000,ID,false)
        pr_lib.Notify({title='XT Prison',description='Atualize/reinicie o PR Bridge para carregar o serviço de emotes.',type='error'})
        return
    end
    local session=hackSession
    local stage='preparação da animação'
    local runOk,runError=xpcall(function()
    if drilling then
        local p=zone.animation
        SetEntityCoordsNoOffset(PlayerPedId(),p.x,p.y,p.z,false,false,false)
        SetEntityHeading(PlayerPedId(),p.w)
        pr_lib.requestAnimDict('anim@heists@fleeca_bank@drilling')
        FreezeEntityPosition(PlayerPedId(),true)
        TaskPlayAnim(PlayerPedId(),'anim@heists@fleeca_bank@drilling','drill_straight_idle',8.0,-8.0,-1,1,0,false,false,false)
    else hackSession.emoteStarted=true;config.Emote('tablet2') end
    stage='carregamento/execução do Glitch'
    local ok, success = xpcall(function() return prisonBreakcfg.GateHackMinigame(ID) end,hackTraceback)
    if hackSession~=session then return end -- logout/resource cleanup cancelled this attempt
    if not ok then error('Não foi possível iniciar '..tostring(zone.game)..': '..tostring(success),0) end
    success=success==true
    stage='processamento do resultado'
    -- Glitch may unfreeze on exit. Hold position until progress + server commit;
    -- otherwise a successful minigame can be rejected by the final distance check.
    FreezeEntityPosition(PlayerPedId(),true)

    TriggerServerEvent('xt-prison:server:setPrisonAlarmsChance', success, ID)
    TriggerServerEvent('xt-prison:server:removePrisonbreakItems', success, ID)

    if success then
        stage='progresso/destrancamento das portas'
        if pr_lib.progressCircle({
            label = locale('input.hacking'),
            duration = (prisonBreakcfg.HackLength * 1000),
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = {
                move = true,
                car = true,
                combat = true,
                sprint = true
            },
        }) then
            local unlocked,reason=pr_lib.callback.await('xt-prison:server:completeTerminal',15000,ID)
            pr_lib.Notify({title=unlocked and locale('notify.completed_hack') or 'Não foi possível destrancar as portas deste terminal.',description=not unlocked and tostring(reason or 'Confira o diagnóstico no console do servidor.') or nil,type=unlocked and 'success' or 'error'})
        end
    else
        pr_lib.Notify({ title = locale('notify.failed_hack'), type = 'error' })
    end
    end,hackTraceback)
    if hackSession==session then cleanupHack() end
    if not runOk then
        XTPrison.log('error',('Terminal %s | %s | %s\n%s'):format(ID,tostring(zone.game),stage,tostring(runError)))
        local reason=tostring(runError):match('^[^\r\n]+') or tostring(runError)
        pr_lib.Notify({title='XT Prison',description=('%s: %s\nDiagnóstico completo no F8.'):format(tostring(zone.game),reason:sub(1,240)),type='error'})
    end
    local released,releaseError=pcall(pr_lib.callback.await,'xt-prison:server:setTerminalBusyState',15000,ID,false)
    if not released then XTPrison.log('error',tostring(releaseError)) end
end

local targetRevision=0
local targetsActive=true
local function rebuildHackZones()
    targetRevision=targetRevision+1
    local revision=targetRevision
    prisonBreakModules.removeHackZones()
    local function attempt(remaining)
        if not targetsActive or revision~=targetRevision or not XTPrison.settings then return end
        if not prisonBreakModules.createHackZones() and remaining>0 then SetTimeout(1000,function() attempt(remaining-1) end) end
    end
    attempt(5)
end
AddEventHandler('xt-prison:client:configurationUpdated',rebuildHackZones)
AddEventHandler('xt-prison:client:onLoad',function() targetsActive=true;rebuildHackZones() end)
AddEventHandler('xt-prison:client:onUnload',function() targetsActive=false;targetRevision=targetRevision+1;prisonBreakModules.removeHackZones() end)
AddEventHandler('onClientResourceStart',function(resource)
    if resource=='pr_bridge' or resource==GetCurrentResourceName() then targetsActive=true;rebuildHackZones() end
end)

-- Sets Alarm State --
function prisonBreakModules.initAlarm(state,alarms)
    alarmRevision=alarmRevision+1
    local revision=alarmRevision
    if not state then
        for name in pairs(activeAlarmNames) do StopAlarm(name,true) end
        activeAlarmNames={};desiredAlarmNames={};return
    end
    alarms=alarms or prisonBreakcfg.Alarms or {prisonBreakcfg.Alarm or {coords={x=1787.004,y=2593.1984,z=45.7978},interior='int_prison_main',prop='prison_alarm',name='PRISON_ALARMS'}}
    desiredAlarmNames={}
    for _,alarm in ipairs(alarms) do desiredAlarmNames[alarm.name]=true end
    for name in pairs(activeAlarmNames) do if not desiredAlarmNames[name] then StopAlarm(name,true);activeAlarmNames[name]=nil end end
    for _,alarm in ipairs(alarms) do
    if revision~=alarmRevision then return end
    local p=alarm.coords
    local alarmIpl = GetInteriorAtCoordsWithType(p.x,p.y,p.z,alarm.interior)
    if alarmIpl~=0 then RefreshInterior(alarmIpl); EnableInteriorProp(alarmIpl,alarm.prop) end
    if not activeAlarmNames[alarm.name] then
    local deadline=GetGameTimer()+5000
    local prepared=PrepareAlarm(alarm.name)
    while not prepared and GetGameTimer()<deadline and revision==alarmRevision do
        Wait(100)
        prepared=PrepareAlarm(alarm.name)
    end

    if revision~=alarmRevision then return end
    if prepared then
        StartAlarm(alarm.name, true)
        activeAlarmNames[alarm.name]=true
    else
        XTPrison.log('error','Não foi possível preparar o alarme GTA: '..alarm.name)
    end
    end
    end
end

function prisonBreakModules.setEscapeAlarms(states)
    local alarms={}
    for _,escape in ipairs(prisonBreakcfg.Escapes or {}) do
        if states[escape.id] then for _,alarm in ipairs(escape.alarms) do alarms[#alarms+1]=alarm end end
    end
    -- Aggregate by native name: stopping B must not stop A's same GTA alarm.
    prisonBreakModules.initAlarm(#alarms>0,alarms)
end
AddEventHandler('xt-prison:client:escapeAlarmCacheChanged',function(states)
    prisonBreakModules.setEscapeAlarms(type(states)=='table' and states or {})
end)

-- Prison Alarm Toggle --
function prisonBreakModules.setPrisonAlarm(setState)
    if setState then
        prisonBreakModules.initAlarm(true)

        PrisonBreakBlip = utils.createBlip('PRISON BREAK', prisonBreakcfg.Center, 161, 3.0, 3, true)
    else
        prisonBreakModules.initAlarm(false)

        prisonBreakModules.removeBlip()
    end
end

AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then cleanupHack();prisonBreakModules.initAlarm(false);prisonBreakModules.removeBlip() end
end)
AddEventHandler('xt-prison:client:onUnload',cleanupHack)

return prisonBreakModules

