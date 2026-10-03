local config = XTPrison.load 'configs.client'
local prisonConfig = XTPrison.load 'configs.prisonbreak'

local settings
local allowed = false
local laserActive = false
local adminParentMenu
local adminParentResource

local openMainMenu
local openLocationsMenu
local openNpcMenu
local openSpawnsMenu
local openHacksMenu
local openBoundaryMenu
local openBreakoutMenu
local openAlarmsMenu
local openEscapeMenu
local openEscapeDoors
local activeEscapeId
local function activeEscape()
    for _,escape in ipairs(settings and settings.escapes or {}) do
        if escape.id==activeEscapeId then return escape end
    end
end

local function notify(description, kind)
    pr_lib.Notify({
        title = 'XT Prison',
        description = description,
        type = kind or 'inform'
    })
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function plain(value, heading)
    value = value or {}
    local result = {
        x = tonumber(value.x or value[1]) or 0.0,
        y = tonumber(value.y or value[2]) or 0.0,
        z = tonumber(value.z or value[3]) or 0.0,
    }
    if heading then result.w = tonumber(value.w or value[4] or value.heading) or 0.0 end
    return result
end

local function formatCoords(value, heading)
    value = plain(value, heading)
    if heading then
        return ('%.2f, %.2f, %.2f | direção %.1f°'):format(value.x, value.y, value.z, value.w)
    end
    return ('%.2f, %.2f, %.2f'):format(value.x, value.y, value.z)
end

local function currentPosition(heading)
    local coords = GetEntityCoords(PlayerPedId())
    local result = plain(coords)
    if heading then result.w = GetEntityHeading(PlayerPedId()) end
    return result
end

local function teleport(value)
    local coords = plain(value)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
end

local function apply(value)
    if type(value) ~= 'table' then return end
    settings = copy(value)
    XTPrison.settings = settings

    local general = settings.general
    local locations = settings.locations
    config.DebugPoly = general.debugPoly == true
    config.RemoveJob = general.removeJob == true
    config.EnablePrisonOutfits = general.enableOutfits == true
    config.Freedom = vec4(locations.freedom.x, locations.freedom.y, locations.freedom.z, locations.freedom.w)
    config.CheckOut = {
        coords = vec3(locations.checkout.coords.x, locations.checkout.coords.y, locations.checkout.coords.z),
        size = vec3(locations.checkout.size.x, locations.checkout.size.y, locations.checkout.size.z),
        rotation = locations.checkout.rotation,
    }
    config.RosterLocation = {
        coords = vec3(locations.roster.coords.x, locations.roster.coords.y, locations.roster.coords.z),
        radius = locations.roster.radius,
    }

    config.CanteenPed.model = locations.canteen.model
    config.CanteenPed.coords = vec4(locations.canteen.coords.x, locations.canteen.coords.y, locations.canteen.coords.z, locations.canteen.coords.w)
    config.CanteenPed.scenario = locations.canteen.scenario
    config.CanteenPed.mealLength = locations.canteen.duration
    config.PrisonDoctor.model = locations.doctor.model
    config.PrisonDoctor.coords = vec4(locations.doctor.coords.x, locations.doctor.coords.y, locations.doctor.coords.z, locations.doctor.coords.w)
    config.PrisonDoctor.scenario = locations.doctor.scenario
    config.PrisonDoctor.healLength = locations.doctor.duration

    config.Spawns = {}
    for index, spawn in ipairs(locations.spawns or {}) do
        config.Spawns[index] = {
            coords = vec4(spawn.coords.x, spawn.coords.y, spawn.coords.z, spawn.coords.w),
            emote = spawn.emote
        }
    end

    prisonConfig.Center = vec3(locations.prison.center.x, locations.prison.center.y, locations.prison.center.z)
    prisonConfig.Radius = locations.prison.radius
    prisonConfig.Boundary = copy(locations.prison)
    prisonConfig.HackZones = {}
    for index, zone in ipairs(locations.hacks or {}) do
        prisonConfig.HackZones[index] = {
            coords = vec3(zone.coords.x, zone.coords.y, zone.coords.z),
            gate = zone.gate,
            radius = zone.radius
        }
    end

    local breakout = settings.prisonBreak
    prisonConfig.HackLength = breakout.hackLength
    prisonConfig.AlarmLength = breakout.alarmLength
    prisonConfig.TerminalCooldowns = breakout.terminalCooldown
    prisonConfig.MinimumPolice = breakout.minimumPolice
    prisonConfig.AlarmChanceOnHack = { fail = breakout.alarmFailChance, success = breakout.alarmSuccessChance }
    prisonConfig.RemoveItemsChanceOnHack = { fail = breakout.removeFailChance, success = breakout.removeSuccessChance }
    XTPrison.load('modules.break_settings').apply(settings, config, prisonConfig)

    TriggerEvent('xt-prison:client:configurationUpdated')
end

local function fetch()
    local payload = pr_lib.callback.await('xt-prison:server:getSettings',20000)
    if type(payload) ~= 'table' or type(payload.settings)~='table' then return false end
    allowed = payload.allowed == true
    apply(payload.settings)
    return true
end

local function save(reopen)
    if not settings then return end
    local response = pr_lib.callback.await('xt-prison:server:saveSettings', 60000, settings)
    if not response or response.ok ~= true then
        notify(response and response.error or 'Não foi possível salvar a configuração.', 'error')
        return
    end
    apply(response.settings)
    notify('Configuração salva e publicada para todos os jogadores.', 'success')
    if reopen then SetTimeout(150, reopen) end
end

local function register(menu)
    pr_lib.RegisterContext(menu)
    pr_lib.ShowContext(menu.id)
end

local function captureLaser(callback, cancel)
    local devlaser = pr_lib.devlaser or pr_lib.devLaser or (pr_lib.fivem and (pr_lib.fivem.devlaser or pr_lib.fivem.devLaser))
    if not devlaser or not devlaser.start or not devlaser.getTarget then
        notify('A ferramenta Draw Laser do PR Bridge não está disponível.', 'error')
        if cancel then cancel() end
        return
    end
    if laserActive then return end

    laserActive = true
    pr_lib.ShowTextUI('[ENTER] Selecionar ponto  |  [BACKSPACE] Cancelar')
    devlaser.start({
        distance = 1000.0,
        flags = -1,
        onStop = function()
            if not laserActive then return end
            laserActive = false
            pr_lib.HideTextUI()
            if cancel then cancel() end
        end
    })

    CreateThread(function()
        while laserActive and devlaser.isActive and devlaser.isActive() do
            Wait(0)
            if IsControlJustReleased(0, 201) or IsDisabledControlJustReleased(0, 201) then
                local hit = devlaser.getTarget()
                if hit and hit.coords then
                    laserActive = false
                    pr_lib.HideTextUI()
                    devlaser.stop(true)
                    callback(plain(hit.coords))
                else
                    notify('Nenhum ponto válido foi localizado.', 'error')
                end
            elseif IsControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 177)
                or IsControlJustReleased(0, 202) or IsDisabledControlJustReleased(0, 202) then
                laserActive = false
                pr_lib.HideTextUI()
                devlaser.stop(true)
                if cancel then cancel() end
            end
        end
    end)
end

local function editGeneral()
    local value = settings.general
    local result = pr_lib.InputDialog('Configurações gerais', {
        { type = 'checkbox', label = 'Exibir zonas de depuração', checked = value.debugPoly },
        { type = 'checkbox', label = 'Remover emprego ao prender', checked = value.removeJob },
        { type = 'checkbox', label = 'Aplicar uniforme da prisão', checked = value.enableOutfits },
        { type = 'checkbox', label = 'Ativar comando /jail', checked = value.enableJailCommand },
        { type = 'checkbox', label = 'Ativar target de consulta da pena', checked = value.checkoutEnabled ~= false },
    })
    if not result then return openMainMenu() end
    value.debugPoly = result[1] == true
    value.removeJob = result[2] == true
    value.enableOutfits = result[3] == true
    value.enableJailCommand = result[4] == true
    value.checkoutEnabled = result[5] == true
    save(openMainMenu)
end

local function editSentence()
    local value = settings.sentence
    local result = pr_lib.InputDialog('Regras de tempo de prisão', {
        { type = 'select', label = 'Unidade padrão', default = value.defaultUnit, required = true, options = {
            { label = 'Minutos', value = 'minutes' },
            { label = 'Horas', value = 'hours' },
            { label = 'Dias', value = 'days' },
        }},
        { type = 'select', label = 'Relógio padrão', default = value.defaultClock, required = true, options = {
            { label = 'Vida real', value = 'real' },
            { label = 'Tempo do jogo', value = 'game' },
        }},
        { type = 'number', label = 'Segundos reais por minuto do jogo', default = value.gameMinuteSeconds, min = 1, max = 3600, required = true },
        { type = 'number', label = 'Quantidade máxima informada', default = value.maxAmount, min = 1, max = 1000000, required = true },
    })
    if not result then return openMainMenu() end
    value.defaultUnit = result[1]
    value.defaultClock = result[2]
    value.gameMinuteSeconds = tonumber(result[3])
    value.maxAmount = tonumber(result[4])
    save(openMainMenu)
end

local function editBreakout()
    local value = settings.prisonBreak
    local result = pr_lib.InputDialog('Configuração da fuga', {
        { type = 'number', label = 'Duração do hack (segundos)', default = value.hackLength, min = 1, required = true },
        { type = 'number', label = 'Cooldown dos terminais (minutos)', default = value.terminalCooldown, min = 0, required = true },
        { type = 'number', label = 'Policiais mínimos', default = value.minimumPolice, min = 0, required = true },
        { type = 'number', label = 'Remover item ao falhar (%)', default = value.removeFailChance, min = 0, max = 100, required = true },
        { type = 'number', label = 'Remover item ao concluir (%)', default = value.removeSuccessChance, min = 0, max = 100, required = true },
    })
    if not result then return openMainMenu() end
    local keys = { 'hackLength', 'terminalCooldown', 'minimumPolice', 'removeFailChance', 'removeSuccessChance' }
    for index, key in ipairs(keys) do value[key] = tonumber(result[index]) end
    save(openMainMenu)
end

local function pointMenu(id, title, value, heading, onChange, parent)
    register({
        id = id,
        title = title,
        menu = parent,
        options = {
            {
                title = 'Usar minha posição',
                description = formatCoords(currentPosition(heading), heading),
                icon = 'geo-alt-fill',
                onSelect = function()
                    onChange(currentPosition(heading))
                    save(function() pointMenu(id, title, value, heading, onChange, parent) end)
                end
            },
            {
                title = 'Selecionar com Draw Laser',
                description = 'Mire no local e pressione ENTER.',
                icon = 'crosshair',
                onSelect = function()
                    captureLaser(function(point)
                        if heading then point.w = GetEntityHeading(PlayerPedId()) end
                        onChange(point)
                        save(function() pointMenu(id, title, value, heading, onChange, parent) end)
                    end, function() pointMenu(id, title, value, heading, onChange, parent) end)
                end
            },
            {
                title = 'Teleportar para o local',
                description = formatCoords(value, heading),
                icon = 'cursor-fill',
                metadata = {
                    { label = 'X', value = ('%.3f'):format(value.x) },
                    { label = 'Y', value = ('%.3f'):format(value.y) },
                    { label = 'Z', value = ('%.3f'):format(value.z) },
                },
                onSelect = function()
                    teleport(value)
                    pointMenu(id, title, value, heading, onChange, parent)
                end
            }
        }
    })
end

local function editCheckout()
    local value = settings.locations.checkout
    local result = pr_lib.InputDialog('Área de checkout', {
        { type = 'number', label = 'Largura (X)', default = value.size.x, min = 0.1, required = true },
        { type = 'number', label = 'Comprimento (Y)', default = value.size.y, min = 0.1, required = true },
        { type = 'number', label = 'Altura (Z)', default = value.size.z, min = 0.1, required = true },
        { type = 'number', label = 'Rotação', default = value.rotation, min = 0, max = 360, required = true },
    })
    if not result then return openLocationsMenu() end
    value.size = { x = tonumber(result[1]), y = tonumber(result[2]), z = tonumber(result[3]) }
    value.rotation = tonumber(result[4])
    save(openLocationsMenu)
end

local function editRoster()
    local value = settings.locations.roster
    local result = pr_lib.InputDialog('Área do roster', {
        { type = 'number', label = 'Raio', default = value.radius, min = 0.1, max = 25, required = true },
    })
    if not result then return openLocationsMenu() end
    value.radius = tonumber(result[1])
    save(openLocationsMenu)
end

local function placeNpc(key, parent, index)
    local npc = index and settings.npcs[key][index] or settings.locations[key]
    local tools = pr_lib.devtools or (pr_lib.fivem and (pr_lib.fivem.devtools or pr_lib.fivem.devTools))
    if not tools or type(tools.placePed) ~= 'function' then
        notify('O posicionador de NPC do PR Bridge não está disponível.', 'error')
        return openNpcMenu()
    end
    notify('Posicione o NPC e pressione ENTER para salvar.', 'inform')
    local started = tools.placePed(npc.model, 1, function(result)
        if not result then return openNpcMenu() end
        local coords = result.coords or result.position or result
        npc.coords = plain(coords, true)
        npc.coords.w = tonumber(result.heading or result.w or (result.rotation and result.rotation.z) or npc.coords.w) or 0.0
        save(openNpcMenu)
    end, {
        freezePlayer = true,
        moveSpeed = 0.6,
        preview = true
    })
    if not started then
        notify('Já existe uma ferramenta de posicionamento ativa.', 'error')
        openNpcMenu()
    end
end

local function editNpc(key, title, index)
    local npc = index and settings.npcs[key][index] or settings.locations[key]
    local result = pr_lib.InputDialog(title, {
        { type = 'input', label = 'Modelo do NPC', default = npc.model, required = true },
        { type = 'input', label = 'Cenário', default = npc.scenario },
        { type = 'number', label = 'Duração da interação (segundos)', default = npc.duration, min = 1, max = 300, required = true },
    })
    if not result then return openNpcMenu() end
    npc.model = tostring(result[1])
    npc.scenario = tostring(result[2] or '')
    npc.duration = tonumber(result[3])
    save(openNpcMenu)
end

openNpcMenu = function()
    local options = {}
    for _, entry in ipairs({
        { key = 'canteen', title = 'NPC da cantina' },
        { key = 'doctor', title = 'Médico da prisão' },
    }) do
        options[#options+1]={title='Adicionar '..entry.title,icon='plus',onSelect=function()
            local npc=copy(settings.locations[entry.key]);npc.coords=currentPosition(true)
            settings.npcs[entry.key][#settings.npcs[entry.key]+1]=npc
            save(openNpcMenu)
        end}
        for index,npc in ipairs(settings.npcs[entry.key]) do
        options[#options + 1] = {
            title = entry.title .. ' #'..index..': dados',
            description = ('%s | %s'):format(npc.model, npc.scenario ~= '' and npc.scenario or 'sem cenário'),
            icon = 'person-gear',
            metadata = {
                { label = 'Modelo', value = npc.model },
                { label = 'Cenário', value = npc.scenario ~= '' and npc.scenario or 'Nenhum' },
                { label = 'Posição', value = formatCoords(npc.coords, true) },
                { label = 'Duração', value = ('%ss'):format(npc.duration) },
            },
            onSelect = function() editNpc(entry.key, entry.title, index) end
        }
        options[#options + 1] = {
            title = entry.title .. ': posicionar e pré-visualizar',
            description = formatCoords(npc.coords, true),
            icon = 'person-bounding-box',
            onSelect = function() placeNpc(entry.key, 'xt_prison_npcs', index) end
        }
        options[#options + 1] = {
            title = entry.title .. ': teleportar',
            icon = 'cursor-fill',
            onSelect = function() teleport(npc.coords); openNpcMenu() end
        }
        options[#options+1]={title='Excluir '..entry.title..' #'..index,icon='trash',iconColor='red',onSelect=function()
            table.remove(settings.npcs[entry.key],index);save(openNpcMenu)
        end}
        end
    end
    register({ id = 'xt_prison_npcs', title = 'NPCs da prisão', menu = 'xt_prison_settings', options = options })
end

local function editSpawn(index)
    local spawn = settings.locations.spawns[index]
    local result = pr_lib.InputDialog(('Ponto de entrada #%s'):format(index), {
        { type = 'input', label = 'Emote ao entrar', default = spawn.emote },
    })
    if not result then return openSpawnsMenu() end
    spawn.emote = tostring(result[1] or '')
    save(openSpawnsMenu)
end

local function spawnActions(index)
    local spawn = settings.locations.spawns[index]
    register({
        id = 'xt_prison_spawn_' .. index,
        title = ('Entrada #%s'):format(index),
        menu = 'xt_prison_spawns',
        options = {
            { title = 'Editar emote', description = spawn.emote ~= '' and spawn.emote or 'Sem emote', icon = 'person-walking', onSelect = function() editSpawn(index) end },
            { title = 'Usar minha posição', description = formatCoords(spawn.coords, true), icon = 'geo-alt-fill', onSelect = function() spawn.coords = currentPosition(true); save(openSpawnsMenu) end },
            { title = 'Selecionar com Draw Laser', icon = 'crosshair', onSelect = function()
                captureLaser(function(point)
                    point.w = GetEntityHeading(PlayerPedId())
                    spawn.coords = point
                    save(openSpawnsMenu)
                end, openSpawnsMenu)
            end },
            { title = 'Teleportar', icon = 'cursor-fill', onSelect = function() teleport(spawn.coords); spawnActions(index) end },
            { title = 'Excluir ponto', icon = 'trash', iconColor = 'red', onSelect = function() table.remove(settings.locations.spawns, index); save(openSpawnsMenu) end },
        }
    })
end

openSpawnsMenu = function()
    local options = {{
        title = 'Adicionar na posição atual',
        description = 'Cria um novo ponto de entrada com direção.',
        icon = 'plus',
        onSelect = function()
            settings.locations.spawns[#settings.locations.spawns + 1] = { coords = currentPosition(true), emote = '' }
            save(openSpawnsMenu)
        end
    }}
    for index, spawn in ipairs(settings.locations.spawns) do
        options[#options + 1] = {
            title = ('Entrada #%s'):format(index),
            description = formatCoords(spawn.coords, true),
            icon = 'door-open',
            metadata = {
                { label = 'Emote', value = spawn.emote ~= '' and spawn.emote or 'Nenhum' },
                { label = 'Posição', value = formatCoords(spawn.coords, true) },
            },
            onSelect = function() spawnActions(index) end
        }
    end
    register({ id = 'xt_prison_spawns', title = 'Pontos de entrada', menu = 'xt_prison_locations', options = options })
end

local function editHack(index)
    local zone = settings.locations.hacks[index]
    local choices={}
    for _,gate in ipairs(activeEscape().doors) do choices[#choices+1]={label=gate,value=gate} end
    local result = pr_lib.InputDialog(('Terminal #%s'):format(index), {
        { type = 'multi-select', label = 'Portas que este terminal destranca', default = zone.gates, options=choices, required = true },
        { type = 'number', label = 'Raio', default = zone.radius, min = 0.1, max = 25, required = true },
        { type = 'input', label = 'Item necessário (vazio = nenhum)', default = zone.item or 'trojan_usb' },
        { type = 'number', label = 'Quantidade do item', default = zone.itemCount or 1, min = 1, max = 100, required = true },
        { type = 'select', label = 'Minigame Glitch', default = zone.game or 'CircuitBreaker', required = true, options = {
            {label='Circuit Breaker',value='CircuitBreaker'}, {label='Data Cracker',value='DataCrack'},
            {label='Brute Force',value='BruteForce'}, {label='Plasma Drill',value='PlasmaDrilling'}, {label='Fleeca Drill',value='FleecaDrilling'}
        }},
        { type = 'number', label = 'Dificuldade (Circuit: 0–3; demais: 1–10)', default = zone.difficulty or 3, min = 0, max = 10, required = true },
        { type = 'number', label = 'Vidas (Brute Force)', default = zone.lives or 5, min = 1, max = 20, required = true },
        { type = 'number', label = 'Nível (Circuit Breaker)', default = zone.level or 1, min = 1, max = 6, required = true },
    })
    if not result then return openHacksMenu() end
    zone.gates = result[1]
    zone.gate = zone.gates[1] or ''
    zone.radius = tonumber(result[2])
    zone.item,zone.itemCount,zone.game=tostring(result[3] or ''),tonumber(result[4]),result[5]
    zone.difficulty,zone.lives,zone.level=tonumber(result[6]),tonumber(result[7]),tonumber(result[8])
    save(openHacksMenu)
end

local function drawHackSphere(index)
    local zone = settings.locations.hacks[index]
    local tools = pr_lib.devtools
    if not tools or type(tools.drawSphereZone3D) ~= 'function' then
        notify('O editor de SphereZone do PR Bridge não está disponível.', 'error')
        return openHacksMenu()
    end
    local started = tools.drawSphereZone3D({ radius = zone.radius, maxRadius = 25.0 }, function(result)
        if not result then return openHacksMenu() end
        zone.coords = plain(result.coords or result.center or result)
        zone.radius = tonumber(result.radius) or zone.radius
        zone.shape='sphere'; zone.points={}
        save(openHacksMenu)
    end)
    if not started then notify('Já existe um editor 3D ativo.', 'error'); openHacksMenu() end
end

local function drawHackPoly(index)
    local zone=settings.locations.hacks[index]
    local tools=pr_lib.devtools
    if not tools or not tools.drawPolyzone3D then return notify('Editor PolyZone indisponível.','error') end
    tools.drawPolyzone3D({freezePlayer=true,minPoints=3,wallHeight=zone.thickness or 3,minimumHeight=0.1},function(points,bounds)
        if not points then return openHacksMenu() end
        zone.shape='poly'; zone.points={}
        local x,y=0,0
        for i,p in ipairs(points) do zone.points[i]=plain(p); x=x+p.x; y=y+p.y end
        zone.thickness=tonumber(bounds and bounds.thickness) or 3
        local z=(bounds and bounds.minZ and bounds.maxZ) and (bounds.minZ+bounds.maxZ)/2 or points[1].z
        zone.coords={x=x/#points,y=y/#points,z=z}
        save(openHacksMenu)
    end)
end

local function positionHackPed(index)
    local zone=settings.locations.hacks[index]
    local started=XTPrison.placeHackGizmo(zone,function(result)
        if not result then return openHacksMenu() end
        zone.animation=plain(result,true)
        save(openHacksMenu)
    end)
    if not started then notify('Posicionador animado/gizmo indisponível ou ocupado.','error');openHacksMenu() end
end

local function captureHackDoor(index,double)
    local zone=settings.locations.hacks[index]
    if not zone.gate or zone.gate=='' then notify('Cadastre e selecione uma porta desta fuga primeiro.','error');return openEscapeDoors() end
    local function finish(first,second)
        if not first or (double and not second) then return openHacksMenu() end
        if second then
            local a,b=first.coords,second.coords
            if math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z)<0.01 and first.model==second.model then
                notify('Selecione duas folhas diferentes da porta.','error');return openHacksMenu()
            end
        end
        settings.doors[zone.gate]=double and {doors={first,second},maxDistance=2.5,auto=true} or first
        save(openHacksMenu)
    end
    XTPrison.captureDoor(function(first)
        if double and first then SetTimeout(300,function() XTPrison.captureDoor(function(second) finish(first,second) end) end)
        else finish(first) end
    end)
end

local function hackActions(index)
    local zone = settings.locations.hacks[index]
    register({
        id = 'xt_prison_hack_' .. index,
        title = ('Terminal #%s'):format(index),
        menu = 'xt_prison_hacks',
        options = {
            { title = 'Editar dados', description = ('Porta: %s | Raio: %.2f'):format(zone.gate, zone.radius), icon = 'pen', onSelect = function() editHack(index) end },
            { title = 'Escolher hack Glitch, item e dificuldade', description = zone.game, icon = 'controller', onSelect = function() editHack(index) end },
            { title = 'Cadastrar tranca: porta simples', description = 'Feche a porta e selecione seu objeto. Salva no grupo forge-prison.',icon='lock',onSelect=function() captureHackDoor(index,false) end },
            { title = 'Cadastrar tranca: porta dupla', description = 'Selecione as duas folhas fechadas, uma por vez.',icon='lock',onSelect=function() captureHackDoor(index,true) end },
            { title = 'Desenhar SphereZone', description = formatCoords(zone.coords), icon = 'circle', onSelect = function() drawHackSphere(index) end },
            { title = 'Desenhar PolyZone do hack', icon = 'bounding-box', onSelect = function() drawHackPoly(index) end },
            { title = 'Animação do hack + gizmo', description = 'Pré-visualização animada e ajuste fino segurando a ferramenta.', icon = 'person-bounding-box', onSelect = function() positionHackPed(index) end },
            { title = 'Usar minha posição para a animação', icon = 'geo-alt-fill', onSelect = function() zone.animation=currentPosition(true); save(openHacksMenu) end },
            { title = 'Usar minha posição', icon = 'geo-alt-fill', onSelect = function() zone.coords = currentPosition(false); save(openHacksMenu) end },
            { title = 'Selecionar com Draw Laser', icon = 'crosshair', onSelect = function() captureLaser(function(point) zone.coords = point; save(openHacksMenu) end, openHacksMenu) end },
            { title = 'Teleportar', icon = 'cursor-fill', onSelect = function() teleport(zone.coords); hackActions(index) end },
            { title = 'Excluir terminal', icon = 'trash', iconColor = 'red', onSelect = function() table.remove(settings.locations.hacks, index); save(openHacksMenu) end },
        }
    })
end

openHacksMenu = function()
    local escape=activeEscape()
    if not escape then return openBreakoutMenu() end
    local options = {{
        title = 'Adicionar terminal',
        description = 'Cria na sua posição atual e permite desenhar a zona em seguida.',
        icon = 'plus',
        onSelect = function()
            settings.locations.hacks[#settings.locations.hacks + 1] = { coords = currentPosition(false), gate = '', gates={}, escapeId=escape.id, radius = 0.4 }
            save(openHacksMenu)
        end
    }}
    for index, zone in ipairs(settings.locations.hacks) do
        if zone.escapeId==escape.id then
        options[#options + 1] = {
            title = ('Terminal #%s'):format(index),
            description = ('%s | raio %.2f'):format(zone.gate, zone.radius),
            icon = 'laptop',
            metadata = {
                { label = 'Porta', value = zone.gate },
                { label = 'Posição', value = formatCoords(zone.coords) },
                { label = 'Raio', value = tostring(zone.radius) },
            },
            onSelect = function() hackActions(index) end
        }
        end
    end
    register({ id = 'xt_prison_hacks', title = escape.name..' — terminais', menu = 'xt_prison_escape', options = options })
end

local function drawBoundary(shape)
    local boundary = settings.locations.prison
    local tools = pr_lib.devtools
    if not tools then return notify('As ferramentas 3D do PR Bridge não estão disponíveis.', 'error') end

    if shape == 'poly' then
        local started = tools.drawPolyzone3D({
            freezePlayer = true,
            minPoints = 3,
            wallHeight = boundary.thickness or 20.0,
            heightStep = 0.5,
            minimumHeight = 1.0,
        }, function(points, bounds)
            if not points then return openBoundaryMenu() end
            boundary.shape = 'poly'
            boundary.points = {}
            for index, point in ipairs(points) do boundary.points[index] = plain(point) end
            boundary.thickness = tonumber(bounds and bounds.thickness) or boundary.thickness
            boundary.minZ = tonumber(bounds and bounds.minZ) or boundary.minZ
            boundary.maxZ = tonumber(bounds and bounds.maxZ) or boundary.maxZ
            local x, y, z = 0.0, 0.0, 0.0
            for _, point in ipairs(boundary.points) do x=x+point.x; y=y+point.y; z=z+point.z end
            boundary.center = { x=x/#boundary.points, y=y/#boundary.points, z=z/#boundary.points }
            save(openBoundaryMenu)
        end)
        if not started then notify('Já existe um editor 3D ativo.', 'error'); openBoundaryMenu() end
    else
        local started = tools.drawSphereZone3D({ radius = boundary.radius, maxRadius = 2000.0 }, function(result)
            if not result then return openBoundaryMenu() end
            boundary.shape = 'sphere'
            boundary.center = plain(result.coords or result.center or result)
            boundary.radius = tonumber(result.radius) or boundary.radius
            save(openBoundaryMenu)
        end)
        if not started then notify('Já existe um editor 3D ativo.', 'error'); openBoundaryMenu() end
    end
end

openBoundaryMenu = function()
    local value = settings.locations.prison
    register({
        id = 'xt_prison_boundary',
        title = 'Limite da prisão',
        menu = 'xt_prison_locations',
        options = {
            {
                title = 'Desenhar SphereZone',
                description = ('Atual: %s | raio %.1f m'):format(value.shape, value.radius),
                icon = 'circle',
                onSelect = function() drawBoundary('sphere') end
            },
            {
                title = 'Desenhar PolyZone',
                description = ('Atual: %s | %s pontos'):format(value.shape, #(value.points or {})),
                icon = 'bounding-box',
                onSelect = function() drawBoundary('poly') end
            },
            {
                title = 'Teleportar ao centro',
                description = formatCoords(value.center),
                icon = 'cursor-fill',
                metadata = {
                    { label = 'Formato', value = value.shape == 'poly' and 'PolyZone' or 'SphereZone' },
                    { label = 'Pontos', value = tostring(#(value.points or {})) },
                    { label = 'Raio', value = tostring(value.radius) },
                },
                onSelect = function() teleport(value.center); openBoundaryMenu() end
            }
        }
    })
end

openLocationsMenu = function()
    local locations = settings.locations
    register({
        id = 'xt_prison_locations',
        title = 'Locais e zonas',
        menu = 'xt_prison_settings',
        options = {
            {
                title = 'Ponto de liberdade',
                description = formatCoords(locations.freedom, true),
                icon = 'unlock',
                onSelect = function()
                    pointMenu('xt_prison_freedom', 'Ponto de liberdade', locations.freedom, true, function(value) locations.freedom = value end, 'xt_prison_locations')
                end
            },
            {
                title = 'Checkout da pena',
                description = formatCoords(locations.checkout.coords),
                icon = 'hourglass',
                onSelect = function()
                    register({
                        id = 'xt_prison_checkout_settings',
                        title = 'Checkout da pena',
                        menu = 'xt_prison_locations',
                        options = {
                            { title = 'Editar dimensões', description = ('%.1f x %.1f x %.1f'):format(locations.checkout.size.x, locations.checkout.size.y, locations.checkout.size.z), icon = 'bounding-box', onSelect = editCheckout },
                            { title = 'Usar minha posição', icon = 'geo-alt-fill', onSelect = function() locations.checkout.coords = currentPosition(false); save(openLocationsMenu) end },
                            { title = 'Selecionar com Draw Laser', icon = 'crosshair', onSelect = function() captureLaser(function(point) locations.checkout.coords = point; save(openLocationsMenu) end, openLocationsMenu) end },
                            { title = 'Teleportar', icon = 'cursor-fill', onSelect = function() teleport(locations.checkout.coords); openLocationsMenu() end },
                        }
                    })
                end
            },
            {
                title = 'Roster público',
                description = formatCoords(locations.roster.coords),
                icon = 'clipboard-data',
                onSelect = function()
                    register({
                        id = 'xt_prison_roster_settings',
                        title = 'Roster público',
                        menu = 'xt_prison_locations',
                        options = {
                            { title = 'Editar raio', description = tostring(locations.roster.radius), icon = 'circle', onSelect = editRoster },
                            { title = 'Usar minha posição', icon = 'geo-alt-fill', onSelect = function() locations.roster.coords = currentPosition(false); save(openLocationsMenu) end },
                            { title = 'Selecionar com Draw Laser', icon = 'crosshair', onSelect = function() captureLaser(function(point) locations.roster.coords = point; save(openLocationsMenu) end, openLocationsMenu) end },
                            { title = 'Teleportar', icon = 'cursor-fill', onSelect = function() teleport(locations.roster.coords); openLocationsMenu() end },
                        }
                    })
                end
            },
            { title = 'Limite da prisão', description = locations.prison.shape == 'poly' and 'PolyZone' or 'SphereZone', icon = 'bounding-box-circles', onSelect = openBoundaryMenu },
            { title = 'Pontos de entrada', description = ('%s configurados'):format(#locations.spawns), icon = 'door-open', onSelect = openSpawnsMenu },
            { title = 'Terminais de fuga', description = ('%s configurados'):format(#locations.hacks), icon = 'laptop', onSelect = openHacksMenu },
        }
    })
end

openAlarmsMenu=function()
    local escape=activeEscape()
    if not escape then return openBreakoutMenu() end
    local options={{title='Adicionar ponto de alarme',icon='plus',onSelect=function()
        local alarm=copy(settings.prisonBreak.alarm);alarm.coords=currentPosition(false)
        escape.alarms[#escape.alarms+1]=alarm;save(openAlarmsMenu)
    end},{title='Testar: acionar alarmes agora',description='Independe da chance. Para falha garantida no hack, configure 100%.',icon='bell',onSelect=function()
        local ok=pr_lib.callback.await('xt-prison:server:testAlarm',15000,true,escape.id)
        notify(ok and 'Teste de alarme acionado. Confira o som e o console.' or 'Não foi possível acionar o alarme.',ok and 'success' or 'error')
        openAlarmsMenu()
    end},{title='Parar alarmes de teste',onSelect=function() pr_lib.callback.await('xt-prison:server:testAlarm',15000,false,escape.id);openAlarmsMenu() end}}
    for index,alarm in ipairs(escape.alarms) do
        options[#options+1]={title='Alarme #'..index,description=formatCoords(alarm.coords),icon='bell',onSelect=function()
            register({id='xt_prison_alarm_'..index,title='Alarme #'..index,menu='xt_prison_alarms',options={
                {title='Posicionar ponto',onSelect=function() pointMenu('xt_prison_alarm_pos','Alarme',alarm.coords,false,function(value) alarm.coords=value end,'xt_prison_alarms') end},
                {title='Nome, interior e prop',onSelect=function()
                    local result=pr_lib.InputDialog('Alarme GTA',{
                        {type='input',label='Interior',default=alarm.interior,required=true},
                        {type='input',label='Interior prop',default=alarm.prop,required=true},
                        {type='input',label='Nome nativo do alarme',default=alarm.name,required=true}
                    })
                    if result then alarm.interior=result[1];alarm.prop=result[2];alarm.name=result[3];save(openAlarmsMenu) else openAlarmsMenu() end
                end},
                {title='Excluir ponto',icon='trash',onSelect=function() table.remove(escape.alarms,index);save(openAlarmsMenu) end}
            }})
        end}
    end
    register({id='xt_prison_alarms',title=escape.name..' — alarmes',menu='xt_prison_escape',options=options})
end

openEscapeMenu=function()
    local escape=activeEscape()
    if not escape then return openBreakoutMenu() end
    register({id='xt_prison_escape',title=escape.name,menu='xt_prison_breakout',options={
        {title='Portas desta fuga',description='Cadastrar porta simples/dupla ou selecionar tranca existente.',icon='lock',onSelect=openEscapeDoors},
        {title='Locais de fuga e hacks Glitch',description='Adicionar vários pontos; escolher hack, item, porta e animação com gizmo.',icon='laptop',onSelect=openHacksMenu},
        {title='Regras gerais da fuga',description='Duração do hack, cooldown, consumo de item e policiais mínimos.',icon='sliders',onSelect=editBreakout},
        {title='Regras do alarme desta fuga',icon='bell',onSelect=function()
            local result=pr_lib.InputDialog('Alarme — '..escape.name,{
                {type='number',label='Duração (minutos)',default=escape.alarmLength,min=0,max=1440,required=true},
                {type='number',label='Acionar ao falhar (%)',default=escape.alarmFailChance,min=0,max=100,required=true},
                {type='number',label='Acionar ao concluir (%)',default=escape.alarmSuccessChance,min=0,max=100,required=true}
            })
            if result then escape.alarmLength=result[1];escape.alarmFailChance=result[2];escape.alarmSuccessChance=result[3];save(openEscapeMenu) else openEscapeMenu() end
        end},
        {title='Pontos de alarme e teste',description='Adicionar, editar, excluir, acionar e parar.',icon='bell',onSelect=openAlarmsMenu},
        {title='Verificar trancas registradas',icon='lock',onSelect=function()
            local status=pr_lib.callback.await('xt-prison:server:doorStatus',15000)
            local options={}
            for _,gate in ipairs(escape.doors) do local id=status and status[gate];options[#options+1]={title=gate,description=id and ('Registrada — ID '..id) or 'Não registrada: capture a porta.'} end
            register({id='xt_prison_door_status',title='Trancas — '..escape.name,menu='xt_prison_escape',options=options})
        end},
        {title='Renomear fuga',onSelect=function()
            local result=pr_lib.InputDialog('Nome da fuga',{{type='input',label='Nome',default=escape.name,required=true}})
            if result then escape.name=result[1];save(openEscapeMenu) else openEscapeMenu() end
        end},
        {title='Excluir ambiente de fuga',icon='trash',onSelect=function()
            if pr_lib.AlertDialog({header='Excluir '..escape.name..'?',content='Remove os terminais e alarmes desta fuga. As trancas permanecem cadastradas e fechadas.',cancel=true})~='confirm' then return openEscapeMenu() end
            for i=#settings.locations.hacks,1,-1 do if settings.locations.hacks[i].escapeId==escape.id then table.remove(settings.locations.hacks,i) end end
            for i,v in ipairs(settings.escapes) do if v.id==escape.id then table.remove(settings.escapes,i);break end end
            activeEscapeId=nil;save(openBreakoutMenu)
        end}
    }})
end

openEscapeDoors=function()
    local escape=activeEscape()
    if not escape then return openBreakoutMenu() end
    local function capture(double)
        local result=pr_lib.InputDialog('Cadastrar porta',{{type='input',label='Nome da porta',required=true}})
        if not result then return openEscapeDoors() end
        local gate=('xt-prison:%s:%s'):format(escape.id,result[1]):sub(1,100)
        local function finish(first,second)
            if not first or (double and not second) then return openEscapeDoors() end
            if second and first.model==second.model and math.abs(first.coords.x-second.coords.x)+math.abs(first.coords.y-second.coords.y)+math.abs(first.coords.z-second.coords.z)<0.01 then
                notify('Selecione duas folhas diferentes.','error');return openEscapeDoors()
            end
            settings.doors[gate]=double and {doors={first,second},maxDistance=2.5,auto=true} or first
            local found=false;for _,name in ipairs(escape.doors) do if name==gate then found=true end end
            if not found then escape.doors[#escape.doors+1]=gate end
            save(openEscapeDoors)
        end
        XTPrison.captureDoor(function(first)
            if double and first then SetTimeout(300,function() XTPrison.captureDoor(function(second) finish(first,second) end) end)
            else finish(first) end
        end)
    end
    local options={
        {title='Cadastrar porta simples',onSelect=function() capture(false) end},
        {title='Cadastrar porta dupla',onSelect=function() capture(true) end},
        {title='Selecionar porta já registrada',onSelect=function()
            local catalog=pr_lib.callback.await('xt-prison:server:doorCatalog',15000)
            local choices={};local used={}
            for _,other in ipairs(settings.escapes) do for _,name in ipairs(other.doors) do used[name]=true end end
            for _,door in ipairs(type(catalog)=='table' and catalog or {}) do if not used[door.name] then choices[#choices+1]={value=door.name,label=door.name..' (#'..door.id..')'} end end
            local result=pr_lib.InputDialog('Selecionar tranca',{{type='select',label='Porta',options=choices,required=true}})
            if result then escape.doors[#escape.doors+1]=result[1];save(openEscapeDoors) else openEscapeDoors() end
        end}
    }
    for _,gate in ipairs(escape.doors) do options[#options+1]={title=gate,description='Selecione esta porta nos dados de um terminal.'} end
    register({id='xt_prison_escape_doors',title=escape.name..' — portas',menu='xt_prison_escape',options=options})
end

openBreakoutMenu=function()
    local options={{title='Criar ambiente de fuga',icon='plus',onSelect=function()
        local result=pr_lib.InputDialog('Nova fuga',{{type='input',label='Nome da fuga',required=true}})
        if not result then return openBreakoutMenu() end
        local id;local serial=settings.nextEscapeId or 1
        repeat id='escape_'..serial;serial=serial+1;local found=false
            for _,escape in ipairs(settings.escapes) do if escape.id==id then found=true end end
            if not found then break end
        until false
        settings.nextEscapeId=serial
        settings.escapes[#settings.escapes+1]={id=id,name=result[1],doors={},alarms={}}
        activeEscapeId=id;save(openEscapeMenu)
    end},{title='Regras gerais da fuga',onSelect=editBreakout}}
    for _,escape in ipairs(settings.escapes or {}) do
        local count=0;for _,zone in ipairs(settings.locations.hacks) do if zone.escapeId==escape.id then count=count+1 end end
        options[#options+1]={title=escape.name,description=('%s terminais | %s portas | %s alarmes'):format(count,#escape.doors,#escape.alarms),onSelect=function() activeEscapeId=escape.id;openEscapeMenu() end}
    end
    register({id='xt_prison_breakout',title='Ambientes de fuga',menu='xt_prison_settings',options=options})
end

openMainMenu = function()
    if not settings and not fetch() then
        notify('Não foi possível carregar as configurações.', 'error')
        return
    end
    if not allowed then
        notify('Você não tem permissão para abrir esta configuração.', 'error')
        return
    end

    register({
        id = 'xt_prison_settings',
        title = 'Configuração do XT Prison',
        menu = adminParentMenu,
        menuResource = adminParentResource,
        options = {
            { title = 'Regras da pena', description = 'Minutos, horas, dias, vida real ou tempo do jogo.', icon = 'hourglass-split', onSelect = editSentence },
            { title = 'Configurações gerais', description = 'Emprego, uniforme, debug e comando.', icon = 'sliders', onSelect = editGeneral },
            { title = 'Locais e zonas', description = 'Draw Laser, SphereZone, PolyZone e teleporte.', icon = 'geo-alt-fill', onSelect = openLocationsMenu },
            { title = 'NPCs', description = 'Modelo, cenário, pré-visualização e posicionamento.', icon = 'people-fill', onSelect = openNpcMenu },
            { title = 'Fuga da prisão', description = 'Locais, hacks Glitch, portas, animações e alarmes.', icon = 'shield-lock', onSelect = function() openBreakoutMenu() end },
            { title = 'Aviso ao entrar na prisão', icon = 'chat', onSelect = function()
                local v=settings.entryAlert
                local result=pr_lib.InputDialog('Aviso de entrada',{
                    {type='checkbox',label='Ativar aviso',checked=v.enable},
                    {type='input',label='Título',default=v.header},
                    {type='textarea',label='Mensagem',default=v.content}
                })
                if result then v.enable=result[1]==true; v.header=result[2] or ''; v.content=result[3] or ''; save(openMainMenu) else openMainMenu() end
            end },
            { title = 'Alarmes por ambiente de fuga', icon = 'bell', onSelect = openBreakoutMenu },
        }
    })
end

local function openAdminMenu(parentMenu, parentResource)
    adminParentMenu = type(parentMenu) == 'string' and parentMenu ~= '' and parentMenu or nil
    adminParentResource = type(parentResource) == 'string' and parentResource ~= '' and parentResource or nil

    if adminParentMenu and not adminParentResource then
        adminParentResource = GetInvokingResource()
    end
    if adminParentResource == GetCurrentResourceName() then
        adminParentResource = nil
    end

    fetch()
    openMainMenu()
end

RegisterNetEvent('xt-prison:client:settingsUpdated', apply)
RegisterNetEvent('xt-prison:client:openSettings', openAdminMenu)

exports('OpenAdminMenu', openAdminMenu)

CreateThread(function()
    for attempt=1,10 do
        Wait(1000)
        local ok,result=pcall(fetch)
        if ok and result then return end
        if not ok then XTPrison.log('error','Carregamento das configurações: '..tostring(result)) end
    end
    XTPrison.log('error','Não foi possível sincronizar as configurações iniciais e os targets da prisão.')
end)
