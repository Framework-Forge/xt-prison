-- Exercise the actual installed doorlock state function, not an always-true export.
local root='E:/[FIVEM]/Forge-Core/resources/'
local file=assert(io.open(root..'[ox]/ox_doorlock/server/main.lua','r'))
local text=file:read('*a');file:close()
local body=assert(text:match('(local function setDoorState%(id, state, lockpick%).-\nend)%s*RegisterNetEvent'))
local door={id=17,name='prison',state=1,groups={police=1}}
local handler,notifications
local env=setmetatable({source=0,doors={[17]=door},isAuthorised=function() return false end,
    TriggerClientEvent=function() end,TriggerEvent=function() end,
    locale=function(key) return key end,pr_lib={notify={Notify=function() notifications=true end}}},{__index=_G})
handler=assert(load(body..'\nreturn setDoorState','doorlock-state','t',env))()
assert(handler(17,0)==false and door.state==1,'source 0 denies export even for a registered door')
env.source=23;assert(handler(17,0)==false and door.state==1 and notifications)
env.GetResourceState=function() return 'started' end
env.exports={ox_doorlock={getDoorFromName=function() return {id=door.id,name=door.name,state=door.state} end}}
env.TriggerEvent=function(name,id,state)
    if name~='ox_doorlock:setState' then return end
    local previous=env.source;env.source=''
    handler(id,state);env.source=previous
end
local provider=assert(loadfile(root..'[forge]/[forge-scripts]/pr_bridge/bridge/doorlock/server.lua','t',env))()
assert(provider.setState('prison',false) and door.state==0 and env.source==23)
assert(provider.setState('prison',true) and door.state==1)
env.TriggerEvent=function() end
local ok,reason=provider.setState('prison',false)
assert(not ok and reason=='door_state_not_applied','A missing/no-op event must not report success')
print('PASS: actual doorlock rejects inherited source; trusted bridge event opens with readback and preserves ACL')
