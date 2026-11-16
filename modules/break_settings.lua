local api = {}
api.games = {'CircuitBreaker', 'DataCrack', 'BruteForce', 'PlasmaDrilling', 'FleecaDrilling'}
local valid = {}; for _, game in ipairs(api.games) do valid[game] = true end
local function finite(value, fallback, low, high)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then value = fallback end
    return math.max(low, math.min(high, value))
end
local function point(value, heading)
    value = type(value)=='table' and value or {}
    local result = {}
    for _, axis in ipairs({'x','y','z'}) do result[axis]=finite(value[axis],0,-20000,20000) end
    if heading then result.w=finite(value.w,0,-3600,3600) end
    return result
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function doorLeaf(raw)
    assert(type(raw)=='table' and type(raw.coords)=='table','Geometria da porta inválida')
    local model=tonumber(raw.model)
    assert(model and model==model and math.abs(model)<=4294967295 and model%1==0,'Modelo da porta inválido')
    local leaf={coords=point(raw.coords),model=model,heading=finite(raw.heading,0,-3600,3600),rotation=point(raw.rotation or {z=raw.heading or 0})}
    for _,state in ipairs({'closed','open'}) do
        if type(raw[state])=='table' then leaf[state]={coords=point(raw[state].coords),rotation=point(raw[state].rotation)} end
    end
    return leaf
end
function api.normalize(settings)
    local client = XTPrison.load 'configs.client'
    settings.entryAlert = type(settings.entryAlert)=='table' and settings.entryAlert or {
        enable=client.EnterPrisonAlert.enable, header=client.EnterPrisonAlert.header, content=client.EnterPrisonAlert.content
    }
    settings.entryAlert.enable=settings.entryAlert.enable==true
    settings.entryAlert.header=tostring(settings.entryAlert.header or ''):sub(1,200)
    settings.entryAlert.content=tostring(settings.entryAlert.content or ''):sub(1,2000)
    local breakout=settings.prisonBreak
    breakout.alarm=type(breakout.alarm)=='table' and breakout.alarm or {
        coords={x=1787.004,y=2593.1984,z=45.7978}, interior='int_prison_main', prop='prison_alarm', name='PRISON_ALARMS'
    }
    breakout.alarm.coords=point(breakout.alarm.coords)
    for _,key in ipairs({'interior','prop','name'}) do breakout.alarm[key]=tostring(breakout.alarm[key] or ''):sub(1,100) end
    breakout.alarms=type(breakout.alarms)=='table' and breakout.alarms or {copy(breakout.alarm)}
    for i,alarm in ipairs(breakout.alarms) do
        assert(i<=20,'Máximo de 20 pontos de alarme')
        alarm.coords=point(alarm.coords)
        for _,key in ipairs({'interior','prop','name'}) do alarm[key]=tostring(alarm[key] or breakout.alarm[key]):sub(1,100) end
    end
    settings.npcs=type(settings.npcs)=='table' and settings.npcs or {}
    for _,kind in ipairs({'canteen','doctor'}) do
        settings.npcs[kind]=type(settings.npcs[kind])=='table' and settings.npcs[kind] or {copy(settings.locations[kind])}
        for i,npc in ipairs(settings.npcs[kind]) do
            assert(i<=30,'Máximo de 30 NPCs por tipo')
            npc.model=tostring(npc.model or ''):sub(1,100)
            assert(npc.model~='','Modelo de NPC vazio')
            npc.coords=point(npc.coords,true)
            npc.scenario=tostring(npc.scenario or ''):sub(1,100)
            npc.duration=finite(npc.duration,5,1,300)
        end
    end
    local doors={}
    for name,raw in pairs(type(settings.doors)=='table' and settings.doors or {}) do
        assert(type(name)=='string' and #name<=100,'Nome da porta inválido')
        local definition
        if raw.doors then
            assert(#raw.doors==2,'Porta dupla precisa de duas folhas')
            definition={doors={doorLeaf(raw.doors[1]),doorLeaf(raw.doors[2])}}
        else definition=doorLeaf(raw) end
        definition.maxDistance=finite(raw.maxDistance,2.5,0.1,10)
        definition.doorType=(raw.doorType=='slide' or raw.doorType=='rotate') and raw.doorType or nil
        definition.groups={police=1}
        definition.auto=raw.auto==true
        definition.slideDistance=finite(raw.slideDistance,4,0.1,20)
        definition.slideDirection=point(raw.slideDirection or {x=1,y=0,z=0})
        definition.openAngle=finite(raw.openAngle,90,-360,360)
        definition.openSpeed=finite(raw.openSpeed,1,0.1,10)
        definition.closeSpeed=finite(raw.closeSpeed,1,0.1,10)
        doors[name]=definition
    end
    settings.doors=doors
    -- Migrate the old flat editor without losing terminals or alarm points.
    if type(settings.escapes)~='table' then
        settings.escapes={{id='legacy',name='Fuga original',alarms=copy(breakout.alarms),doors={}}}
        local seen={}
        for _,zone in ipairs(settings.locations.hacks) do
            zone.escapeId='legacy'
            for _,gate in ipairs(zone.gates or {zone.gate}) do
                if gate and not seen[gate] then
                    seen[gate]=true;table.insert(settings.escapes[1].doors,gate)
                end
            end
        end
    end
    local escapes,owners={},{}
    settings.nextEscapeId=math.floor(finite(settings.nextEscapeId,1,1,1000000000))
    for i,escape in ipairs(settings.escapes) do
        assert(i<=30,'Máximo de 30 ambientes de fuga')
        assert(type(escape.id)=='string' and escape.id:match('^[%w_-]+$') and #escape.id<=60 and not escapes[escape.id],'ID de fuga inválido ou duplicado')
        escapes[escape.id]=escape
        local serial=tonumber(escape.id:match('^escape_(%d+)$'))
        if serial then settings.nextEscapeId=math.max(settings.nextEscapeId,serial+1) end
        escape.name=tostring(escape.name or escape.id):sub(1,100)
        escape.alarmLength=finite(escape.alarmLength,breakout.alarmLength or 2,0,1440)
        escape.alarmFailChance=finite(escape.alarmFailChance,100,0,100)
        escape.alarmSuccessChance=finite(escape.alarmSuccessChance,breakout.alarmSuccessChance or 100,0,100)
        escape.doors=type(escape.doors)=='table' and escape.doors or {}
        local seen={}
        for j,gate in ipairs(escape.doors) do
            assert(j<=100 and type(gate)=='string' and gate~='' and #gate<=100 and not seen[gate],'Porta de fuga inválida ou duplicada')
            assert(not owners[gate],'Uma porta não pode pertencer a duas fugas')
            seen[gate]=true;owners[gate]=escape.id
        end
        escape.alarms=type(escape.alarms)=='table' and escape.alarms or {}
        for j,alarm in ipairs(escape.alarms) do
            assert(j<=20,'Máximo de 20 alarmes por fuga')
            alarm.coords=point(alarm.coords)
            for _,key in ipairs({'interior','prop','name'}) do alarm[key]=tostring(alarm[key] or breakout.alarm[key]):sub(1,100) end
        end
    end
    for _,zone in ipairs(settings.locations.hacks) do
        assert(escapes[zone.escapeId],'Terminal sem ambiente de fuga válido')
        zone.gates=type(zone.gates)=='table' and zone.gates or {zone.gate}
        local seen={}
        for i,gate in ipairs(zone.gates) do
            assert(i<=100 and owners[gate]==zone.escapeId and not seen[gate],'Selecione portas pertencentes à fuga do terminal')
            seen[gate]=true
        end
        zone.gate=zone.gates[1] or ''
        zone.coords=point(zone.coords)
        zone.radius=finite(zone.radius,0.4,0.1,25)
        zone.game=valid[zone.game] and zone.game or 'CircuitBreaker'
        zone.item=tostring(zone.item or 'trojan_usb'):sub(1,100)
        zone.itemCount=math.floor(finite(zone.itemCount,1,1,100))
        zone.difficulty=math.floor(finite(zone.difficulty,3,zone.game=='CircuitBreaker' and 0 or 1,zone.game=='CircuitBreaker' and 3 or 10))
        zone.lives=math.floor(finite(zone.lives,5,1,20))
        zone.level=math.floor(finite(zone.level,1,1,6))
        zone.animation=zone.animation and point(zone.animation,true) or nil
        if zone.animation then
            local dx,dy,dz=zone.animation.x-zone.coords.x,zone.animation.y-zone.coords.y,zone.animation.z-zone.coords.z
            assert(dx*dx+dy*dy+dz*dz<=100,'Animation position must be within 10m of terminal')
        end
        zone.shape=zone.shape=='poly' and 'poly' or 'sphere'
        zone.thickness=finite(zone.thickness,3,0.1,50)
        local points={}
        for i,p in ipairs(type(zone.points)=='table' and zone.points or {}) do
            assert(i<=64,'Maximum 64 polygon points')
            points[i]=point(p)
        end
        zone.points=points
        if zone.shape=='poly' then assert(#points>=3,'Polygon requires at least 3 points') end
    end
    return settings
end
function api.apply(settings, client, prison)
    client.EnterPrisonAlert=settings.entryAlert
    if client.CheckOut then client.CheckOut.enabled=settings.general.checkoutEnabled~=false end
    prison.Alarm=settings.prisonBreak.alarm
    prison.Alarms=settings.prisonBreak.alarms
    prison.Doors=settings.doors
    prison.Escapes=settings.escapes
    for _,entry in ipairs({{'canteen','CanteenPeds','mealLength'},{'doctor','PrisonDoctors','healLength'}}) do
        client[entry[2]]={}
        for _,npc in ipairs(settings.npcs[entry[1]]) do
            local p=npc.coords
            client[entry[2]][#client[entry[2]]+1]={model=npc.model,coords=vec4(p.x,p.y,p.z,p.w),scenario=npc.scenario,[entry[3]]=npc.duration}
        end
    end
    for index,zone in ipairs(settings.locations.hacks) do
        local target=prison.HackZones[index]
        for _,key in ipairs({'escapeId','gates','game','item','itemCount','difficulty','lives','level','animation','shape','points','thickness'}) do target[key]=zone[key] end
    end
end
function api.contains(zone,coords)
    if zone.shape~='poly' then
        local dx,dy,dz=coords.x-zone.coords.x,coords.y-zone.coords.y,coords.z-zone.coords.z
        return dx*dx+dy*dy+dz*dz<9
    end
    if math.abs(coords.z-zone.coords.z)>(zone.thickness or 3)/2+1 then return false end
    local inside=false
    local points=zone.points or {}; local j=#points
    for i,p in ipairs(points) do
        local q=points[j]
        if (p.y>coords.y)~=(q.y>coords.y) and coords.x<(q.x-p.x)*(coords.y-p.y)/(q.y-p.y)+p.x then inside=not inside end
        j=i
    end
    return inside
end
return api
