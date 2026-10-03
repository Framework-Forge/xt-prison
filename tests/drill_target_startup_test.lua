local bridge='E:/[FIVEM]/Forge-Core/resources/[forge]/[forge-scripts]/pr_bridge/'
local available=true
GetResourceState=function(name) return available and name=='glitch-minigames' and 'started' or 'stopped' end
local movies={}
RequestScaleformMovie=function(name) movies[#movies+1]=name;return #movies end
HasScaleformMovieLoaded=function() return true end
SetScaleformMovieAsNoLongerNeeded=function() end
GetGameTimer=function() return 0 end
local calls={}
local function export(name)
    return function(_,...) calls[#calls+1]={name=name,args=table.pack(...)};return true end
end
exports={['glitch-minigames']={StartDrilling=export('Fleeca'),StartPlasmaDrilling=export('Plasma'),
    StartDataCrack=export('Data'),StartBruteForce=export('Brute'),StartCircuitBreaker=export('Circuit')}}
pr_lib={requestAnimDict=function() end,requestModel=function() end}
-- No ActiveBridges table: explicit adapter load must work independently of fallback.
local adapter=dofile(bridge..'bridge/minigames/glitch/client.lua')
vec3=function(x,y,z) return {x=x,y=y,z=z} end
local cfg=dofile('configs/prisonbreak.lua')
XTPrison={load=function() return cfg end}
pr_lib.load=function(path) assert(path=='@pr_bridge/bridge/minigames/glitch/client');return adapter end
pr_lib.minigame={Start=function() error('Generic fallback must never run') end}
cfg.HackZones={{game='FleecaDrilling'},{game='PlasmaDrilling',difficulty=7},{game='DataCrack',difficulty=3},
    {game='BruteForce',lives=4},{game='CircuitBreaker',level=2,difficulty=1}}
for i=1,5 do assert(cfg.GateHackMinigame(i)) end
assert(calls[1].name=='Fleeca' and calls[1].args.n==0)
assert(calls[2].name=='Plasma' and calls[2].args[1]==7 and calls[2].args.n==1)
assert(calls[3].args[1]==3 and calls[4].args[1]==4 and calls[5].args[1]==2 and calls[5].args[2]==1)
assert(#movies==1 and movies[1]=='VAULT_LASER','Fleeca must not initialize a second scaleform in the bridge')
local realFleeca=exports['glitch-minigames'].StartDrilling
exports['glitch-minigames'].StartDrilling=function() return false end
assert(cfg.GateHackMinigame(1)==false,'A failed Fleeca result is not an initialization exception')
exports['glitch-minigames'].StartDrilling=function() error('Fleeca export failure') end
local fleecaOk,fleecaError=pcall(cfg.GateHackMinigame,1)
assert(not fleecaOk and tostring(fleecaError):find('Fleeca export failure',1,true),'Preserve the original Fleeca export error')
exports['glitch-minigames'].StartDrilling=realFleeca
available=false;assert(not pcall(cfg.GateHackMinigame,1));available=true
print('PASS: exact five export signatures; Fleeca zero-argument direct call, false result/error propagation, no bridge scaleform init')

local events,timers,targets={},{},{}
AddEventHandler=function(name,fn) events[name]=events[name] or {};table.insert(events[name],fn) end
SetTimeout=function(_,fn) timers[#timers+1]=fn end
local function emit(name,...) for _,fn in ipairs(events[name] or {}) do fn(...) end end
GetCurrentResourceName=function() return 'xt-prison' end
locale=function(key) return key end
PlayerPedId=function() return 5 end
local animations,cleanups,releases,notifications=0,0,0,{}
TaskPlayAnim=function(_,dict,anim) assert(dict=='anim@heists@fleeca_bank@drilling' and anim=='drill_straight_idle');animations=animations+1 end
SetEntityCoordsNoOffset=function() end;SetEntityHeading=function() end
FreezeEntityPosition=function() end;ClearPedTasks=function() end
local attemptEffects=0
TriggerServerEvent=function() attemptEffects=attemptEffects+1 end
cfg.MinimumPolice=0
cfg.Escapes={}
cfg.HackZones={
    {game='FleecaDrilling',coords=vec3(1,2,3),radius=1,animation={x=1,y=2,z=3,w=90}},
    {game='PlasmaDrilling',difficulty=7,coords=vec3(4,5,6),radius=1,animation={x=4,y=5,z=6,w=180}}
}
XTPrison.world={PrisonTerminal_1={isHacked=false,isBusy=false},PrisonTerminal_2={isHacked=false,isBusy=false}}
XTPrison.settings=nil
local diagnosticLogs={}
XTPrison.log=function(level,message) diagnosticLogs[#diagnosticLogs+1]={level=level,message=message} end
XTPrison.load=function(path) if path=='configs.prisonbreak' then return cfg end;return {} end
local realLoad=pr_lib.load
pr_lib.load=function(path)
    if path=='@pr_bridge/bridge/emotes/client' then return {beginSession=function() return {ped=5} end,finishSession=function() cleanups=cleanups+1 end} end
    return realLoad(path)
end
pr_lib.callback={await=function(_,_,_,state) if state==false then releases=releases+1 end;return true end}
pr_lib.Notify=function(message) notifications[#notifications+1]=message end
pr_lib.progressCircle=function() return true end
local sequence,failSecond=0,false
pr_lib.target={addSphereZone=function(definition)
    if failSecond and definition.name=='xt_prison_hack_2' then error('provider not ready') end
    sequence=sequence+1;targets[sequence]=definition;return sequence
end,removeZone=function(id) targets[id]=nil end}
local function count() local n=0;for _ in pairs(targets) do n=n+1 end;return n end
local client=dofile('modules/client/prisonbreak.lua')
assert(client.createHackZones()==false and count()==0,'Do not build obsolete default zones before settings')
XTPrison.settings={};emit('xt-prison:client:configurationUpdated');assert(count()==2)
emit('xt-prison:client:configurationUpdated');assert(count()==2,'Configuration refresh cannot duplicate targets')
for _,target in pairs(targets) do assert(target.options[1].canInteract()) end
failSecond=true;emit('xt-prison:client:configurationUpdated');assert(count()==0,'Partial creation must roll back')
failSecond=false;timers[#timers]();assert(count()==2,'Retry must restore every target')
emit('xt-prison:client:onUnload');assert(count()==0)
emit('xt-prison:client:onLoad');assert(count()==2)
emit('onClientResourceStart','pr_bridge');assert(count()==2)
client.startGateHack(1);client.startGateHack(2)
assert(animations==2 and cleanups==2 and releases==2)
local before=attemptEffects
available=false;client.startGateHack(1)
assert(cleanups==3 and releases==3 and attemptEffects==before,'Initialization errors must not consume item or trigger alarm as a failed hack')
assert(diagnosticLogs[#diagnosticLogs].message:find('Terminal 1 | FleecaDrilling',1,true))
assert(diagnosticLogs[#diagnosticLogs].message:find('stack traceback:',1,true))
assert(notifications[#notifications].description:find('Glitch minigames indisponível',1,true),'Notification must include actual cause, not just tell user to inspect F8')
available=true
print('PASS: target startup/settings refresh/partial rollback/retry/logout/restart and both actual drill flows animate and clean up')

-- A shared adapter loading failure must be diagnosed for every configured game.
local gameNames={'FleecaDrilling','PlasmaDrilling','CircuitBreaker','DataCrack','BruteForce'}
pr_lib.load=function(path)
    if path=='@pr_bridge/bridge/minigames/glitch/client' then error('file glitch adapter unavailable') end
    return realLoad(path)
end
for _,game in ipairs(gameNames) do
    cfg.HackZones[1].game=game
    local ok,err=pcall(cfg.GateHackMinigame,1)
    assert(not ok and tostring(err):find('file glitch adapter unavailable',1,true),game)
end
print('PASS: all five games share the explicit bridge adapter loading path')
