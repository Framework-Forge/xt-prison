-- Real normalization and server execution with isolated cache/provider doubles.
local cfg={HackZones={},Escapes={},AlarmLength=2,TerminalCooldowns=1,MinimumPolice=0}
local timers,world,revision,doors={},{},1,{}
pr_lib={cache={get=function() return revision end},inventory={GetItemCount=function() return 10 end}}
SetTimeout=function(_,fn) timers[#timers+1]=fn end
XTPrison={world=world,load=function(path)
    if path=='configs.prisonbreak' then return cfg end
    if path=='configs.client' then return {EnterPrisonAlert={enable=false}} end
    if path=='modules.server.utils' then return {terminalDistanceCheck=function() return true end,banPlayer=function() error('unexpected ban') end} end
    return {}
end,setGateState=function(name,locked) if name=='broken' then return false end;doors[name]=locked;return true end}
local normalize=dofile('modules/break_settings.lua').normalize
local settings={general={},prisonBreak={},locations={hacks={{gate='a',coords={x=0,y=0,z=0}}}}}
normalize(settings)
assert(settings.escapes[1].id=='legacy' and settings.locations.hacks[1].escapeId=='legacy')
assert(settings.locations.hacks[1].gates[1]=='a' and settings.escapes[1].doors[1]=='a')
settings.escapes[2]={id='B',name='Fuga B',doors={'b'},alarms={}}
settings.locations.hacks[2]={escapeId='B',gates={'b'},coords={x=0,y=0,z=0}}
normalize(settings)
settings.locations.hacks[2].gates={'a'}
assert(not pcall(normalize,settings),'Cross-escape door should be rejected')
settings.locations.hacks[2].gates={'b'}
normalize(settings)
settings.nextEscapeId=8
normalize(settings);assert(settings.nextEscapeId==8,'Saved ID sequence must survive deletion/reload')
cfg.Escapes=settings.escapes
cfg.HackZones={
    {escapeId='legacy',gates={'a','shared'},item='',game='CircuitBreaker'},
    {escapeId='B',gates={'b'},item='',game='CircuitBreaker'},
    {escapeId='legacy',gates={'shared'},item='',game='CircuitBreaker'},
    {escapeId='B',gates={'new','broken'},item='',game='CircuitBreaker'},
    {escapeId='B',gates={'b'},item='',game='FleecaDrilling'}
}
for i=1,#cfg.HackZones do world['PrisonTerminal_'..i]={isHacked=false,isBusy=false} end
local api=dofile('modules/server/prisonbreak.lua')
assert(not api.setEscapeAlarm('unknown',true))
assert(api.setEscapeAlarm('legacy',true));local timerA=timers[#timers]
assert(api.setEscapeAlarm('B',true))
timerA();assert(world.escapeAlarms.legacy==false and world.escapeAlarms.B==true)
assert(api.setEscapeAlarm('B',false) and world.escapeAlarms.B==false)
api.setEscapeAlarm('B',true);local staleAlarm=timers[#timers];revision=revision+1
staleAlarm();assert(world.escapeAlarms.B==true,'Old revision timer must not mutate current world')
assert(api.setTerminalBusyState(1,1,true))
assert(api.setTerminalHackedState(1,1,true));local cooldownA=timers[#timers]
assert(doors.a==false and doors.shared==false and doors.b==nil)
assert(api.setTerminalBusyState(1,3,true));assert(api.setTerminalHackedState(1,3,true))
local cooldownShared=timers[#timers]
cooldownA();assert(doors.a==true and doors.shared==false,'Other active terminal must retain shared door')
cooldownShared();assert(doors.shared==true)
assert(api.setTerminalBusyState(1,4,true))
assert(api.setTerminalHackedState(1,4,true)==false)
assert(doors.new==true and not world.PrisonTerminal_4.isHacked,'Partial unlock must roll back')
assert(api.setTerminalBusyState(1,5,true)==false,'Drill requires configured animated position')
assert(api.setTerminalBusyState(1,2,true));assert(api.setTerminalHackedState(1,2,true))
local staleCooldown=timers[#timers];revision=revision+1;staleCooldown();assert(doors.b==false)
print('PASS: escape migration, door ownership, scoped alarms, multi-door rollback, shared cooldown and drill requirement')

-- Real server door synchronization must include doors not yet used by a terminal.
local callbacks,registered,created={},{},{}
cfg.Escapes={{id='A',doors={'D1','D2'},alarms={}},{id='B',doors={'D3'},alarms={}}}
cfg.HackZones={{escapeId='A',gates={'D1','D2'},gate='D1'}}
cfg.Doors={D1={model=1},D2={model=2},D3={model=3}}
local provider={getByName=function(name) return created[name] end,
    ensure=function(name,definition,group)
        assert(definition.model and group=='forge-prison')
        if not created[name] then created[name]={id=#registered+1};registered[#registered+1]=name end
        return created[name].id
    end,setState=function(name) return created[name]~=nil end,
    catalog=function() return {{id=1,name='D1',doorGroup='forge-prison'},{id=9,name='Casa',doorGroup='forge-housing'}} end}
pr_lib.load=function() return provider end
pr_lib.callback={register=function(name,fn) callbacks[name]=fn end}
local previousLoad=XTPrison.load
XTPrison.load=function(path)
    if path=='modules.server.utils' then return {isAdmin=function(src) return src==1 end} end
    return previousLoad(path)
end
XTPrison.log=function() end
GetResourceState=function() return 'started' end
AddEventHandler=function() end
TriggerClientEvent=function(_,_,ids) assert(#ids==3) end
dofile('server/sv_doors.lua')
local sync=XTPrison.synchronizeDoors()
assert(#sync.ids==3 and #sync.failures==0 and #registered==3)
local status=callbacks['xt-prison:server:doorStatus']()
assert(status.D1 and status.D2 and status.D3)
assert(#callbacks['xt-prison:server:doorCatalog'](1)==1)
assert(#callbacks['xt-prison:server:doorCatalog'](2)==0)
XTPrison.synchronizeDoors();assert(#registered==3,'Existing doors must not be duplicated')
print('PASS: actual prison door sync registers the whole escape pool, preserves IDs and filters housing/admin catalog')
