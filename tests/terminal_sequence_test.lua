local cfg={MinimumPolice=0,TerminalCooldowns=1,HackLength=1,HackZones={
    {game='FleecaDrilling',escapeId='A',gate='a',gates={'a'},item='',animation={x=0,y=0,z=0,w=0}},
    {game='DataCrack',escapeId='B',gate='b',gates={'b'},item=''},
    {game='DataCrack',escapeId='B',gate='b',gates={'b'},item=''},
    {game='DataCrack',escapeId='C',gate='broken',gates={'broken'},item=''}
},Escapes={}}
local world,timers,doors={},{},{}
local near,frozen=true,false
for id=1,4 do world['PrisonTerminal_'..id]={isBusy=false,isHacked=false,gate=cfg.HackZones[id].gate} end
local utils={terminalDistanceCheck=function() return near end,banPlayer=function() error('unexpected ban') end}
pr_lib={cache={get=function() return 1 end},inventory={GetItemCount=function() return 10 end}}
SetTimeout=function(_,callback) timers[#timers+1]=callback end
XTPrison={world=world,load=function(path)
    if path=='configs.prisonbreak' then return cfg end
    if path=='modules.server.utils' then return utils end
    return {}
end,setGateState=function(name,locked)
    if name=='broken' then return false,'door_state_not_applied' end
    doors[name]=locked;return true
end,log=function() end}
local server=dofile('modules/server/prisonbreak.lua')
assert(server.setTerminalBusyState(1,1,true))
assert(server.setTerminalHackedState(1,1,true))
assert(world.PrisonTerminal_1.isBusy==false,'Completion must clear the busy reservation instead of carrying it through cooldown')
assert(world.PrisonTerminal_1.lastHacker==nil,'Completed attempt must discard its owner')
near=false
assert(server.setTerminalBusyState(1,1,false),'Cleanup must be idempotent during cooldown and outside target range')
near=true
assert(server.setTerminalBusyState(1,2,true),'Escape B must be available while A is cooling down')
assert(not server.setTerminalBusyState(2,2,false),'Another player cannot clear a reservation')
assert(not server.setTerminalBusyState(1,2,true),'Duplicate start cannot reset the active attempt')
near=false
assert(server.setTerminalBusyState(1,2,false),'Owned cleanup must not depend on distance')
assert(not server.ownsAttempt(1,2),'A released attempt must not retain authority for side effects')
near=true
assert(server.setTerminalBusyState(1,2,true))
assert(server.setTerminalHackedState(1,2,true))
assert(world.PrisonTerminal_1.isHacked and world.PrisonTerminal_2.isHacked)
assert(doors.a==false and doors.b==false)
assert(server.setTerminalBusyState(1,3,true))
assert(server.setTerminalHackedState(1,3,true),'Other target of an already open door may complete idempotently')
timers[1]();assert(doors.a==true and doors.b==false,'A cooldown must not relock B')
timers[2]();assert(doors.b==false,'B stays open while its other target is still cooling down')
timers[3]();assert(doors.b==true)
assert(server.setTerminalBusyState(1,4,true))
assert(not server.setTerminalHackedState(1,4,true))
assert(server.setTerminalBusyState(1,4,false))
assert(not world.PrisonTerminal_4.isBusy and not world.PrisonTerminal_4.isHacked)
assert(server.setTerminalBusyState(2,4,true),'Rejected completion must allow another retry')
assert(server.setTerminalBusyState(2,4,false))
assert(not server.setTerminalHackedState(2,4,true),'A late completion after release must be rejected without banning')
assert(server.setTerminalBusyState(2,4,true))
assert(server.setTerminalBusyState(3,1,true))
near=false
server.releasePlayerTerminals(2)
assert(not world.PrisonTerminal_4.isBusy and world.PrisonTerminal_1.isBusy,'Disconnect only releases that player reservations')
server.releasePlayerTerminals(3)
assert(not world.PrisonTerminal_1.isBusy)
near=true

-- Execute the actual client flow against the actual server state machine.
local events,notifications,cleanups={},{},0
AddEventHandler=function(name,callback) events[name]=callback end
GetCurrentResourceName=function() return 'xt-prison' end
PlayerPedId=function() return 5 end
FreezeEntityPosition=function(_,state) frozen=state end
ClearPedTasks=function() end
SetEntityCoordsNoOffset=function() end;SetEntityHeading=function() end;TaskPlayAnim=function() end
TriggerServerEvent=function() end
locale=function(key) return key end
cfg.GateHackMinigame=function() frozen=false;return true end -- installed drills unfreeze on completion
XTPrison.settings={}
XTPrison.load=function(path)
    if path=='configs.prisonbreak' then return cfg end
    if path=='configs.client' then return {Emote=function() end} end
    return {}
end
pr_lib.load=function() return {beginSession=function() return {ped=5} end,
    finishSession=function() cleanups=cleanups+1 end} end
pr_lib.requestAnimDict=function() return true end
pr_lib.Notify=function(message) notifications[#notifications+1]=message end
pr_lib.progressCircle=function()
    assert(frozen,'Do not unfreeze the player before the final server distance check')
    return true
end
pr_lib.callback={await=function(name,_,id,state)
    if name=='xt-prison:server:completeTerminal' then return server.setTerminalHackedState(1,id,true) end
    return server.setTerminalBusyState(1,id,state)
end}
local client=dofile('modules/client/prisonbreak.lua')
client.startGateHack(1);client.startGateHack(2)
assert(cleanups==2 and not frozen)
assert(#notifications==2 and notifications[1].type=='success' and notifications[2].type=='success')
assert(not world.PrisonTerminal_1.isBusy and not world.PrisonTerminal_2.isBusy)
assert(not client.canHackTerminal(1),'Hacked target remains inactive during its configured cooldown')
assert(client.canHackTerminal(3),'Other target remains independently available')
timers[4]();assert(client.canHackTerminal(1),'Target reactivates when its own cooldown expires')
client.startGateHack(4)
assert(notifications[#notifications].type=='error' and notifications[#notifications].description:find('door_state_not_applied',1,true))
assert(not world.PrisonTerminal_4.isBusy and client.canHackTerminal(4),'Actual client must release a rejected completion for retry')
client.startGateHack(3)
assert(notifications[#notifications].type=='success' and not world.PrisonTerminal_3.isBusy)
assert(cleanups==4 and not frozen,'Rejected completion must not poison the following target/session')
print('PASS: Fleeca A -> DataCrack B, busy/owner cleanup, failed retry, ownership, shared gates, independent cooldown and final-confirmation freeze')
