local root='E:/[FIVEM]/Forge-Core/resources/[forge]/[forge-scripts]/pr_bridge/bridge/emotes/client.lua'
local objects={[1]={model=10,ped=5},[2]={model=99,ped=5}}
PlayerPedId=function() return 5 end
joaat=function(name) return name=='prop_cs_tablet' and 10 or 20 end
GetGamePool=function() local ids={};for id in pairs(objects) do ids[#ids+1]=id end;return ids end
DoesEntityExist=function(id) return objects[id]~=nil end
GetEntityModel=function(id) return objects[id].model end
IsEntityAttachedToEntity=function(id,ped) return objects[id].ped==ped end
DetachEntity=function() end;SetEntityAsMissionEntity=function() end
DeleteEntity=function(id) objects[id]=nil end
GetResourceState=function() return 'started' end
local cancelled=0
exports={scully_emotemenu={cancelEmote=function() cancelled=cancelled+1 end,playEmoteByCommand=function() end}}
local api=dofile(root)
local session=api.beginSession({'prop_cs_tablet','hei_prop_heist_drill'})
session.emoteStarted=true
objects[3]={model=10,ped=5};objects[4]={model=20,ped=5};objects[5]={model=10,ped=7};objects[6]={model=99,ped=5}
api.finishSession(session)
assert(cancelled==1 and not objects[3] and not objects[4])
assert(objects[1] and objects[2] and objects[5] and objects[6],'Do not delete preexisting, other player or unrelated props')
api.finishSession(session);assert(cancelled==1,'Cleanup is idempotent')
print('PASS: bridge cancels emote and removes only session tablet/drill props')

-- Actual client flow must finalize on success, refusal, minigame/progress errors.
local cfg={HackLength=1,HackZones={{game='DataCrack'}}}
local cleanups,releases,failProgress,failMini,unlock=0,0,false,false,true
cfg.GateHackMinigame=function() if failMini then error('minigame failed') end;return true end
RegisterNetEvent=function() end;AddEventHandler=function() end
GetCurrentResourceName=function() return 'xt-prison' end
ClearPedTasks=function() end;FreezeEntityPosition=function() end
TriggerServerEvent=function() end;locale=function(key) return key end
pr_lib={load=function() return {beginSession=function() return {ped=5} end,finishSession=function() cleanups=cleanups+1 end} end,
    callback={await=function(name,_,_,state)
        if name=='xt-prison:server:completeTerminal' then return unlock end
        if state==false then releases=releases+1 end
        return true
    end},Notify=function() end,progressCircle=function() if failProgress then error('progress failed') end;return true end}
XTPrison={world={},log=function() end,load=function(path)
    if path=='configs.client' then return {Emote=function() end} end
    if path=='configs.prisonbreak' then return cfg end
    return {}
end}
local client=dofile('modules/client/prisonbreak.lua')
client.startGateHack(1)
unlock=false;client.startGateHack(1)
failMini=true;client.startGateHack(1)
failMini=false;failProgress=true;client.startGateHack(1)
assert(cleanups==4 and releases==4)
print('PASS: actual hack success/refusal/minigame error/progress error always clean props and release terminal')
