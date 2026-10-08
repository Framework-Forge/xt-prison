local values,callbacks,rows,metadata={},{},{},{}
local identifier='CHAR_A'
local failSave=false
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
pr_lib={cache={get=function(k) return values[k] end,set=function(k,v) values[k]=v end,clear=function(k) values[k]=nil end},
    framework={GetIdentifier=function() return identifier end,GetPlayer=function() return {} end,
        GetPlayerMetadata=function(_,k) return metadata[k] end,SetPlayerMetadata=function(_,k,v) metadata[k]=v end},
    callback={register=function(k,fn) callbacks[k]=fn end},inventory={}}
IsDuplicityVersion=function() return true end
GetCurrentResourceName=function() return 'xt-prison' end
AddEventHandler=function() end;RegisterNetEvent=function() end;TriggerClientEvent=function() end
CreateThread=function() end;exports=function() end;syncJailCompatibility=function() end
json={encode=copy,decode=function(v) if v=='null' then return nil end;if v=='[]' then return {} end;return copy(v) end}
local db={awaitReady=function() return true end,UPDATE_JAILTIME='SAVE',LOAD_JAILTIME='LOAD',GET_ITEMS='ITEMS',CLEAR_CONFISCATED_ITEMS='CLEAR'}
local breakConfig={Boundary={shape='poly',minZ=0,maxZ=100,points={{x=0,y=0},{x=10,y=0},{x=10,y=10},{x=0,y=10}}},Escapes={}}
XTPrison={log=function() end,load=function(path)
    if path=='modules.server.db' then return db end
    if path=='configs.prisonbreak' then return breakConfig end
    if path=='configs.client' then return {Spawns={{coords={x=20,y=20,z=50,w=0}},{coords={x=5,y=5,z=50,w=90}}}} end
    return {}
end}
pr_lib.database={query=function(sql,args) assert(sql=='LOAD');return rows[args[1]] and {copy(rows[args[1]])} or {} end,
    insert=function(sql,args)
        assert(sql=='SAVE' and args[4],'All writes must include the persistent status')
        if failSave then return false end
        rows[args[1]]={jailtime=args[2],sentence=copy(args[3]),status=args[4]};return 1
    end,scalar=function() return nil end,execute=function() return 1 end}
dofile('bridge/cache.lua');dofile('bridge/server/pr_bridge.lua');dofile('server/sv_main.lua')
pr_lib.addExports=function() end
dofile('server/sv_actions.lua')
local init=callbacks['xt-prison:server:initJailTime']
rows.CHAR_A={jailtime=5,status='jailed',sentence={clock='game',tickSeconds=2,remainingMinutes=5}}
assert(init(1)==5 and metadata.injail==5 and metadata.prisonStatus=='jailed')
assert(XTPrison.prisonStatus(1).spawn.x==5,'Only a configured spawn inside the prison boundary is eligible')
values['xt-prison:action:CHAR_A']=true
assert(not XTPrison.prisonStatus(1),'Uncommitted transitions must not be exposed to the spawn selector')
values['xt-prison:action:CHAR_A']=nil
local position={x=5,y=5,z=50}
GetPlayerPed=function() return 1 end;GetEntityCoords=function() return position end
local escape=dofile('modules/server/prisonbreak.lua')
assert(not escape.prisonBreakout(1),'Cannot report escape while inside prison')
position={x=20,y=20,z=50}
assert(escape.prisonBreakout(1),'Valid outside-boundary escape must commit')
assert(rows.CHAR_A.status=='fugitive' and rows.CHAR_A.jailtime==5 and rows.CHAR_A.sentence.escapedAt)
assert(metadata.injail==0 and metadata.prisonStatus=='fugitive')
XTPrison.clearPlayer(1,identifier)
assert(init(1)==0,'Reconnect must not enter jail for a fugitive')
assert(XTPrison.playerState(1).jailTime==5 and XTPrison.playerState(1).prisonStatus=='fugitive')
assert(callbacks['xt-prison:server:tickJailTime'](1)==0 and rows.CHAR_A.jailtime==5,'Fugitive sentence must not count down')
assert(not callbacks['xt-prison:server:setJailStatus'](1),'Fugitive cannot enter the ordinary jail flow')
assert(setJailSentence(1,{amount=7,clock='real',unit='minutes'}))
assert(XTPrison.persistPlayer(1) and rows.CHAR_A.status=='jailed')
failSave=true
assert(not escape.prisonBreakout(1) and metadata.prisonStatus=='jailed','Failed escape persistence must roll back state')
failSave=false
setJailTime(1,0);assert(XTPrison.persistPlayer(1) and rows.CHAR_A.status=='free' and not rows.CHAR_A.sentence)
XTPrison.clearPlayer(1,identifier);identifier='CHAR_B';metadata={injail=11}
assert(init(1)==11,'Legacy metadata should seed a character without an XT row')
assert(XTPrison.persistPlayer(1) and rows.CHAR_B.status=='jailed')
print('PASS: authoritative escape, DB status, metadata/cache, fugitive reconnect, frozen sentence, re-jail, release, rollback and legacy metadata')
