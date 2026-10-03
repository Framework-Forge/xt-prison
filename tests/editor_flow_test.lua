vec3=function(x,y,z) return {x=x,y=y,z=z} end;vector3=vec3
vec4=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end;vector4=vec4
local modules, menus, exported, hooks={},{},{},{}
XTPrison={load=function(path)
    if not modules[path] then modules[path]=dofile(path:gsub('%.','/')..'.lua') end
    return modules[path]
end,log=function() end}
local cfg=XTPrison.load('configs.client')
local settings={general={checkoutEnabled=true},sentence={},locations={
    freedom=cfg.Freedom,checkout={coords=cfg.CheckOut.coords,size=cfg.CheckOut.size,rotation=0},
    roster=cfg.RosterLocation,prison={center={x=0,y=0,z=0},radius=200,shape='sphere'},
    canteen={model='cook',coords={x=1,y=2,z=3,w=0},scenario='',duration=2},
    doctor={model='doc',coords={x=1,y=2,z=3,w=0},scenario='',duration=3},
    spawns={},hacks={{coords={x=1,y=2,z=3},gate='gate',radius=1}}
},prisonBreak={hackLength=5,alarmLength=2,terminalCooldown=1,minimumPolice=0}}
XTPrison.load('modules.break_settings').normalize(settings)
RegisterNetEvent=function(name,fn) hooks[name]=fn end
AddEventHandler=RegisterNetEvent
TriggerEvent=function() end
CreateThread=function() end
SetTimeout=function(_,fn) fn() end
GetCurrentResourceName=function() return 'xt-prison' end
GetInvokingResource=function() return nil end
PlayerPedId=function() return 1 end
GetEntityCoords=function() return {x=1,y=2,z=3} end
GetEntityHeading=function() return 90 end
exports=function(name,fn) exported[name]=fn end
local saved
pr_lib={RegisterContext=function(menu) menus[menu.id]=menu end,ShowContext=function() end,Notify=function() end,
    callback={await=function(name,_,raw)
        if name=='xt-prison:server:getSettings' then return {allowed=true,settings=settings} end
        if name=='xt-prison:server:saveSettings' then XTPrison.load('modules.break_settings').normalize(raw);settings=raw;saved=raw;return {ok=true,settings=raw} end
        return {}
    end},InputDialog=function(_,fields)
        local result={};for i,field in ipairs(fields) do result[i]=field.default end
        for i,field in ipairs(fields) do if field.label=='Minigame Glitch' then result[i]='FleecaDrilling' end end
        return result
    end}
local captured=0
XTPrison.captureDoor=function(cb) captured=captured+1;cb({coords={x=captured,y=2,z=3},model=123,heading=0,rotation={x=0,y=0,z=0}});return true end
XTPrison.placeHackGizmo=function(_,cb) cb({x=1,y=2,z=3,w=180});return true end
dofile('client/cl_settings.lua')
local function select(menu,title)
    for _,opt in ipairs(assert(menus[menu]).options) do if opt.title:find(title,1,true) then opt.onSelect();return end end
    error('Missing option: '..menu..' / '..title)
end
exported.OpenAdminMenu()
select('xt_prison_settings','Fuga da prisão')
select('xt_prison_breakout','Fuga original')
select('xt_prison_escape','Locais de fuga')
select('xt_prison_hacks','Terminal #1')
select('xt_prison_hack_1','Escolher hack Glitch')
assert(saved.locations.hacks[1].game=='FleecaDrilling')
select('xt_prison_hacks','Terminal #1')
select('xt_prison_hack_1','Animação do hack + gizmo')
assert(saved.locations.hacks[1].animation.w==180)
select('xt_prison_hacks','Terminal #1')
select('xt_prison_hack_1','Cadastrar tranca: porta dupla')
assert(#saved.doors.gate.doors==2)
select('xt_prison_hacks','Adicionar terminal')
assert(#saved.locations.hacks==2)
exported.OpenAdminMenu();select('xt_prison_settings','NPCs')
select('xt_prison_npcs','Adicionar Médico')
assert(#saved.npcs.doctor==2)
select('xt_prison_escape','Pontos de alarme')
select('xt_prison_alarms','Adicionar ponto de alarme')
assert(#saved.escapes[1].alarms==2)
local originalDialog=pr_lib.InputDialog
pr_lib.InputDialog=function() return {'Fuga B'} end
select('xt_prison_breakout','Criar ambiente de fuga')
pr_lib.InputDialog=originalDialog
assert(#saved.escapes==2 and saved.escapes[2].name=='Fuga B' and saved.escapes[2].alarmFailChance==100)
select('xt_prison_escape','Locais de fuga')
assert(#menus.xt_prison_hacks.options==1,'New escape must not show original terminals')
select('xt_prison_hacks','Adicionar terminal')
assert(saved.locations.hacks[3].escapeId==saved.escapes[2].id)
select('xt_prison_escape','Pontos de alarme')
select('xt_prison_alarms','Adicionar ponto de alarme')
assert(#saved.escapes[1].alarms==2 and #saved.escapes[2].alarms==1)
print('PASS: actual menu routes reach Glitch selection, animation, double door capture, multiple hacks/NPCs/alarms')
