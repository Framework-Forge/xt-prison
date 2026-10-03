local root = 'E:/[FIVEM]/Forge-Core/resources/[forge]/[forge-scripts]/pr_bridge/bridge/doorlock/server.lua'
local available, persisted, found, created, edited, locked = true, false, nil, nil, nil, nil
GetResourceState = function() return available and 'started' or 'stopped' end
pr_lib = {database={query=function() return persisted and {{id=7}} or {} end}}
exports = {ox_doorlock={
    getDoorFromName=function(_,name) return found end,
    editDoor=function(_,id,patch) edited=patch end,
    createDoor=function(_,payload) created=payload; return 8 end,
    setDoorState=function(_,id,state) locked=state; return true end,
}}
vec3=function(x,y,z) return {x=x,y=y,z=z} end
TriggerEvent=function(event,id,state) assert(event=='ox_doorlock:setState');locked=state;found.state=state end
local api = dofile(root)
local id, reason = api.ensure('gate',nil,'forge-prison')
assert(not id and reason=='missing_door_geometry')
local definition={coords={x=1,y=2,z=3},model=123,doorType='slide',slideDistance=4,closed={coords={x=1,y=2,z=3}}}
assert(api.ensure('gate',definition,'forge-prison')==8)
assert(created.doorType=='slide' and created.slideDistance==4 and created.closed.coords.x==definition.closed.coords.x)
assert(created.doorGroup=='forge-prison' and created.state==1 and created.distance==80)
assert(not definition.name and not definition.state)
created=nil; persisted=true
id,reason=api.ensure('gate',definition,'forge-prison')
assert(not id and reason=='provider_loading' and not created)
found={id=7}
assert(api.ensure('gate',definition,'forge-prison')==7 and not created)
assert(edited.doorGroup=='forge-prison' and not edited.doorType and not edited.coords)
assert(api.setState('gate',false) and locked==0)
assert(api.setState('gate',true) and locked==1)
found.doorGroup='forge-housing'
id,reason=api.ensure('gate',definition,'forge-prison')
assert(not id and reason=='door_owned_by_other_group')
found.doorGroup=nil
assert(api.ensure('gate',definition,'forge-prison',{groups={police=1}})==7)
assert(edited.groups.police==1 and edited.characters=='' and edited.items=='' and edited.passcode=='' and edited.lockpick==false)
found=nil;persisted=false
assert(api.ensure('new',definition,'forge-prison',{groups={police=1}})==8)
assert(created.groups.police==1 and not created.characters and created.lockpick==false)
available=false
id,reason=api.ensure('gate',definition,'forge-prison')
assert(not id and reason=='provider_unavailable')
print('PASS: door provider creation, preservation, duplicate guard and states')
