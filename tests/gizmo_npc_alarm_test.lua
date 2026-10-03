local hooks,entities,targets,blips={}, {}, {}, {}
local sequence=10
local function hook(name,fn) hooks[name]=hooks[name] or {};table.insert(hooks[name],fn) end
RegisterNetEvent=hook;AddEventHandler=hook
GetCurrentResourceName=function() return 'xt-prison' end
CreateThread=function() end
PlayerPedId=function() return 1 end
GetEntityModel=function() return 123 end
GetEntityCoords=function(id) return entities[id] or {x=0,y=0,z=0} end
GetEntityHeading=function(id) return entities[id] and entities[id].w or 0 end
DoesEntityExist=function(id) return entities[id]~=nil end
DeleteEntity=function(id) entities[id]=nil end;DeletePed=DeleteEntity
CreatePed=function(_,_,x,y,z,w) sequence=sequence+1;entities[sequence]={x=x,y=y,z=z,w=w};return sequence end
CreateObjectNoOffset=function(_,x,y,z) sequence=sequence+1;entities[sequence]={x=x,y=y,z=z};return sequence end
SetEntityCollision=function() end;FreezeEntityPosition=function() end;SetEntityInvincible=function() end
GetPedBoneIndex=function() return 28422 end
local attached,animated
AttachEntityToEntity=function() attached=true end
TaskPlayAnim=function(_,dict,name) animated=dict=='anim@heists@fleeca_bank@drilling' and name=='drill_straight_idle' end
joaat=function() return 999 end
local gizmoOptions
pr_lib={load=function() return {ensureRegistration=function() end} end,
    requestModel=function() end,requestAnimDict=function() end,HideTextUI=function() end,
    devtools={placeAnimatedPed=function(_,_,animations,cb)
        assert(animations[1].animName=='drill_straight_idle')
        cb({x=1,y=2,z=3,heading=90});return true
    end},gizmo={start=function(_,_,_,options) gizmoOptions=options;return true end}}
XTPrison={log=function() end}
dofile('client/cl_door_editor.lua')
local final
assert(XTPrison.placeHackGizmo({game='PlasmaDrilling'},function(result) final=result end))
assert(attached and animated and gizmoOptions)
gizmoOptions.onConfirm()
assert(final.x==1 and final.w==90 and next(entities)==nil)
assert(XTPrison.placeHackGizmo({game='FleecaDrilling'},function(result) final=result end))
gizmoOptions.onCancel();assert(final==nil and next(entities)==nil)
print('PASS: actual animated placement hands drill preview to gizmo; confirm/cancel clean entities')
local notifyMissing=0
pr_lib.Notify=function() notifyMissing=notifyMissing+1 end
pr_lib.load=function() error("file '@pr_bridge/bridge/doorlock/client.lua' not found") end
source=65535
hooks['xt-prison:client:doorsRegistered'][1]({1})
assert(notifyMissing==1,'Missing mounted adapter must inform admin without crashing editor')
pr_lib.load=function() return {ensureRegistration=function(ids) assert(ids[1]==1) end} end
hooks['xt-prison:client:doorsRegistered'][1]({1})
source=nil
print('PASS: missing mounted client adapter is reported safely and can be retried')

local config={CanteenPeds={},PrisonDoctors={}}
for i=1,2 do
    config.CanteenPeds[i]={model='cook',coords={x=i,y=0,z=0,w=0},scenario='',mealLength=1}
    config.PrisonDoctors[i]={model='doc',coords={x=i,y=0,z=0,w=0},scenario='',healLength=1}
end
local utils={createPed=function(_,p) return CreatePed(4,123,p.x,p.y,p.z,p.w) end,
createBlip=function() sequence=sequence+1;blips[sequence]=true;return sequence end}
XTPrison.load=function(path) return path=='configs.client' and config or utils end
pr_lib.target={addLocalEntity=function(ped,options) targets[ped]=options end,removeLocalEntity=function(ped) targets[ped]=nil end}
DoesBlipExist=function(id) return blips[id]~=nil end
RemoveBlip=function(id) blips[id]=nil end
local function emit(name,... ) for _,fn in ipairs(hooks[name] or {}) do fn(...) end end
dofile('client/cl_canteen.lua');dofile('client/cl_infirmary.lua')
emit('xt-prison:client:onLoad')
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
assert(count(entities)==4 and count(targets)==4 and count(blips)==4)
emit('xt-prison:client:configurationUpdated')
assert(count(entities)==4 and count(targets)==4 and count(blips)==4)
emit('xt-prison:client:onUnload')
assert(count(entities)==0 and count(targets)==0 and count(blips)==0)
print('PASS: two canteens and two doctors spawn, refresh without duplicates and unload cleanly')

local breakCfg={Alarms={{coords={x=1,y=2,z=3},interior='prison',prop='alarm',name='A'},{coords={x=4,y=5,z=6},interior='prison',prop='alarm',name='B'}}}
XTPrison.load=function(path)
    if path=='configs.client' then return config end
    if path=='configs.prisonbreak' then return breakCfg end
    return utils
end
XTPrison.world={}
GetInteriorAtCoordsWithType=function() return 100 end;RefreshInterior=function() end;EnableInteriorProp=function() end
PrepareAlarm=function() return true end;GetGameTimer=function() return 0 end
local sounds={}
StartAlarm=function(name) sounds[name]=true end
StopAlarm=function(name) sounds[name]=nil end
local alarmModule=dofile('modules/client/prisonbreak.lua')
alarmModule.initAlarm(true);assert(sounds.A and sounds.B)
alarmModule.initAlarm(false);assert(next(sounds)==nil)
breakCfg.Escapes={{id='A',alarms={breakCfg.Alarms[1]}},{id='B',alarms={breakCfg.Alarms[2]}}}
alarmModule.setEscapeAlarms({A=true});assert(sounds.A and not sounds.B)
alarmModule.setEscapeAlarms({B=true});assert(sounds.B and not sounds.A)
breakCfg.Escapes[2].alarms={breakCfg.Alarms[1]}
alarmModule.setEscapeAlarms({A=true,B=true});assert(sounds.A and not sounds.B)
alarmModule.setEscapeAlarms({B=true});assert(sounds.A,'Stopping A must not stop B using same native name')
alarmModule.setEscapeAlarms({});assert(next(sounds)==nil)
print('PASS: multiple alarm identifiers start and stop without stopping unrelated alarms')
