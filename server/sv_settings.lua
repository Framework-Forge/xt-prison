local clientConfig = XTPrison.load 'configs.client'
local serverConfig = XTPrison.load 'configs.server'
local prisonConfig = XTPrison.load 'configs.prisonbreak'

local settings
local ready = false
local saving = false

local function number(value, fallback, minimum, maximum)
    value = tonumber(value) or fallback
    if minimum then value = math.max(minimum, value) end
    if maximum then value = math.min(maximum, value) end
    return value
end

local function plainVector(value, heading)
    value = value or {}
    local result = {
        x = number(value.x or value[1], 0.0),
        y = number(value.y or value[2], 0.0),
        z = number(value.z or value[3], 0.0),
    }
    if heading then result.w = number(value.w or value[4], 0.0) end
    return result
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = clone(entry) end
    return result
end

local function merge(base, override)
    local result = clone(base)
    if type(override) ~= 'table' then return result end
    if base[1] ~= nil or override[1] ~= nil or (next(override) == nil and base[1] ~= nil) then
        return clone(override)
    end
    for key, value in pairs(override) do
        if type(value) == 'table' and type(result[key]) == 'table' then
            result[key] = merge(result[key], value)
        else
            result[key] = clone(value)
        end
    end
    return result
end

local function defaultSettings()
    local spawns, hacks = {}, {}
    for index, spawn in ipairs(clientConfig.Spawns or {}) do
        spawns[index] = { coords = plainVector(spawn.coords, true), emote = tostring(spawn.emote or '') }
    end
    for index, zone in ipairs(prisonConfig.HackZones or {}) do
        hacks[index] = {
            coords = plainVector(zone.coords),
            gate = tostring(zone.gate or ''),
            radius = number(zone.radius, 0.4, 0.1, 25.0)
        }
    end

    return {
        version = 1,
        general = {
            debugPoly = clientConfig.DebugPoly == true,
            removeJob = clientConfig.RemoveJob == true,
            enableOutfits = clientConfig.EnablePrisonOutfits == true,
            enableJailCommand = serverConfig.EnableJailCommand ~= false,
            checkoutEnabled = clientConfig.CheckOut.enabled ~= false,
        },
        sentence = {
            defaultUnit = 'minutes',
            defaultClock = 'real',
            gameMinuteSeconds = 2,
            maxAmount = 9999,
        },
        locations = {
            freedom = plainVector(clientConfig.Freedom, true),
            checkout = {
                coords = plainVector(clientConfig.CheckOut.coords),
                size = plainVector(clientConfig.CheckOut.size),
                rotation = number(clientConfig.CheckOut.rotation, 0.0),
            },
            roster = {
                coords = plainVector(clientConfig.RosterLocation.coords),
                radius = number(clientConfig.RosterLocation.radius, 0.3, 0.1, 25.0),
            },
            prison = {
                shape = 'sphere',
                center = plainVector(prisonConfig.Center),
                radius = number(prisonConfig.Radius, 200.0, 1.0, 2000.0),
                points = {},
                thickness = 20.0,
                minZ = number(prisonConfig.Center.z, 45.0) - 10.0,
                maxZ = number(prisonConfig.Center.z, 45.0) + 10.0,
            },
            canteen = {
                model = tostring(clientConfig.CanteenPed.model or 's_m_m_linecook'),
                coords = plainVector(clientConfig.CanteenPed.coords, true),
                scenario = tostring(clientConfig.CanteenPed.scenario or ''),
                duration = number(clientConfig.CanteenPed.mealLength, 2, 1, 300),
            },
            doctor = {
                model = tostring(clientConfig.PrisonDoctor.model or 's_m_m_doctor_01'),
                coords = plainVector(clientConfig.PrisonDoctor.coords, true),
                scenario = tostring(clientConfig.PrisonDoctor.scenario or ''),
                duration = number(clientConfig.PrisonDoctor.healLength, 5, 1, 300),
            },
            spawns = spawns,
            hacks = hacks,
        },
        prisonBreak = {
            hackLength = number(prisonConfig.HackLength, 5, 1, 3600),
            alarmLength = number(prisonConfig.AlarmLength, 2, 0, 1440),
            terminalCooldown = number(prisonConfig.TerminalCooldowns, 10, 0, 1440),
            minimumPolice = number(prisonConfig.MinimumPolice, 0, 0, 100),
            alarmFailChance = number(prisonConfig.AlarmChanceOnHack and prisonConfig.AlarmChanceOnHack.fail, 10, 0, 100),
            alarmSuccessChance = number(prisonConfig.AlarmChanceOnHack and prisonConfig.AlarmChanceOnHack.success, 100, 0, 100),
            removeFailChance = number(prisonConfig.RemoveItemsChanceOnHack and prisonConfig.RemoveItemsChanceOnHack.fail, 100, 0, 100),
            removeSuccessChance = number(prisonConfig.RemoveItemsChanceOnHack and prisonConfig.RemoveItemsChanceOnHack.success, 50, 0, 100),
        }
    }
end

local function normalize(raw)
    local value = merge(defaultSettings(), raw)
    local validUnits = { minutes = true, hours = true, days = true }
    value.sentence.defaultUnit = validUnits[value.sentence.defaultUnit] and value.sentence.defaultUnit or 'minutes'
    value.sentence.defaultClock = value.sentence.defaultClock == 'game' and 'game' or 'real'
    value.sentence.gameMinuteSeconds = number(value.sentence.gameMinuteSeconds, 2, 1, 3600)
    value.sentence.maxAmount = math.floor(number(value.sentence.maxAmount, 9999, 1, 1000000))

    value.locations.freedom = plainVector(value.locations.freedom, true)
    value.locations.checkout.coords = plainVector(value.locations.checkout.coords)
    value.locations.checkout.size = plainVector(value.locations.checkout.size)
    value.locations.checkout.rotation = number(value.locations.checkout.rotation, 0.0)
    value.locations.roster.coords = plainVector(value.locations.roster.coords)
    value.locations.roster.radius = number(value.locations.roster.radius, 0.3, 0.1, 25.0)

    local boundary = value.locations.prison
    boundary.shape = boundary.shape == 'poly' and 'poly' or 'sphere'
    boundary.center = plainVector(boundary.center)
    boundary.radius = number(boundary.radius, 200.0, 1.0, 2000.0)
    boundary.thickness = number(boundary.thickness, 20.0, 1.0, 500.0)
    boundary.minZ = number(boundary.minZ, boundary.center.z - boundary.thickness * 0.5)
    boundary.maxZ = number(boundary.maxZ, boundary.center.z + boundary.thickness * 0.5)
    local points = {}
    for _, point in ipairs(type(boundary.points) == 'table' and boundary.points or {}) do
        points[#points + 1] = plainVector(point)
    end
    boundary.points = points
    if boundary.shape == 'poly' and #points < 3 then boundary.shape = 'sphere' end

    for _, key in ipairs({ 'canteen', 'doctor' }) do
        local npc = value.locations[key]
        npc.model = tostring(npc.model or '')
        npc.coords = plainVector(npc.coords, true)
        npc.scenario = tostring(npc.scenario or '')
        npc.duration = number(npc.duration, key == 'canteen' and 2 or 5, 1, 300)
    end

    local spawns = {}
    for _, spawn in ipairs(type(value.locations.spawns) == 'table' and value.locations.spawns or {}) do
        spawns[#spawns + 1] = { coords = plainVector(spawn.coords, true), emote = tostring(spawn.emote or '') }
    end
    value.locations.spawns = spawns

    local hacks = {}
    for index, zone in ipairs(type(value.locations.hacks) == 'table' and value.locations.hacks or {}) do
        assert(index <= 100, 'Maximum 100 terminals')
        local entry = clone(zone)
        entry.coords = plainVector(zone.coords)
        entry.gate = tostring(zone.gate or ''):sub(1,100)
        entry.radius = number(zone.radius, 0.4, 0.1, 25.0)
        hacks[#hacks + 1] = entry
    end
    value.locations.hacks = hacks

    for key, entry in pairs(value.general) do value.general[key] = entry == true end
    local breakDefaults = defaultSettings().prisonBreak
    for key, fallback in pairs(breakDefaults) do
        local maximum = key:find('Chance') and 100 or 100000
        value.prisonBreak[key] = number(value.prisonBreak[key], fallback, 0, maximum)
    end
    return XTPrison.load('modules.break_settings').normalize(value)
end

local function apply(value)
    settings = normalize(value)
    XTPrison.settings = settings

    clientConfig.DebugPoly = settings.general.debugPoly
    clientConfig.RemoveJob = settings.general.removeJob
    clientConfig.EnablePrisonOutfits = settings.general.enableOutfits
    serverConfig.EnableJailCommand = settings.general.enableJailCommand

    local locations = settings.locations
    clientConfig.Freedom = vec4(locations.freedom.x, locations.freedom.y, locations.freedom.z, locations.freedom.w)
    clientConfig.CheckOut = {
        coords = vec3(locations.checkout.coords.x, locations.checkout.coords.y, locations.checkout.coords.z),
        size = vec3(locations.checkout.size.x, locations.checkout.size.y, locations.checkout.size.z),
        rotation = locations.checkout.rotation,
    }
    clientConfig.RosterLocation = {
        coords = vec3(locations.roster.coords.x, locations.roster.coords.y, locations.roster.coords.z),
        radius = locations.roster.radius,
    }
    clientConfig.CanteenPed.model = locations.canteen.model
    clientConfig.CanteenPed.coords = vec4(locations.canteen.coords.x, locations.canteen.coords.y, locations.canteen.coords.z, locations.canteen.coords.w)
    clientConfig.CanteenPed.scenario = locations.canteen.scenario
    clientConfig.CanteenPed.mealLength = locations.canteen.duration
    clientConfig.PrisonDoctor.model = locations.doctor.model
    clientConfig.PrisonDoctor.coords = vec4(locations.doctor.coords.x, locations.doctor.coords.y, locations.doctor.coords.z, locations.doctor.coords.w)
    clientConfig.PrisonDoctor.scenario = locations.doctor.scenario
    clientConfig.PrisonDoctor.healLength = locations.doctor.duration

    clientConfig.Spawns = {}
    for index, spawn in ipairs(locations.spawns) do
        clientConfig.Spawns[index] = {
            coords = vec4(spawn.coords.x, spawn.coords.y, spawn.coords.z, spawn.coords.w),
            emote = spawn.emote
        }
    end

    prisonConfig.Center = vec3(locations.prison.center.x, locations.prison.center.y, locations.prison.center.z)
    prisonConfig.Radius = locations.prison.radius
    prisonConfig.Boundary = clone(locations.prison)
    prisonConfig.HackZones = {}
    for index, zone in ipairs(locations.hacks) do
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
    XTPrison.load('modules.break_settings').apply(settings, clientConfig, prisonConfig)
    TriggerEvent('xt-prison:server:configurationUpdated')
end

local function allowed(source)
    return source == 0 or XTPrison.load('modules.server.utils').isAdmin(source)
        or IsPlayerAceAllowed(source, 'xt-prison.admin')
        or IsPlayerAceAllowed(source, 'group.admin')
        or IsPlayerAceAllowed(source, 'admin')
        or IsPlayerAceAllowed(source, 'command.prisonconfig')
end

local function payload(source)
    return { allowed = allowed(source), settings = clone(settings or defaultSettings()) }
end

local storage = XTPrison.load('modules.server.settings_storage')
CreateThread(function()
    local function initialize()
        local ok, decoded, err = pcall(storage.load)
        if not ok then err, decoded = tostring(decoded), nil end
        if err then XTPrison.log('error', err) end
        apply(decoded or defaultSettings())
        if not err then
            local saved, saveError = storage.save(clone(settings))
            if not saved then XTPrison.log('error', saveError) end
        end
        ready = true
        pr_lib.cache.set('xt-prison:settings', clone(settings))
        TriggerClientEvent('xt-prison:client:settingsUpdated', -1, clone(settings))
        XTPrison.log('info', ('Armazenamento das configuracoes: %s.'):format(storage.mode))
    end
    if storage.mode == 'database' then pr_lib.database.ready(initialize) else initialize() end
end)

pr_lib.callback.register('xt-prison:server:getSettings', function(source)
    local deadline = GetGameTimer() + 15000
    while not ready and GetGameTimer() < deadline do Wait(50) end
    if not ready then return nil end
    return payload(source)
end)

pr_lib.callback.register('xt-prison:server:saveSettings', function(source, raw)
    if not allowed(source) then return { ok = false, error = 'Sem permissão.' } end
    if type(raw) ~= 'table' then return {ok=false,error='Invalid settings'} end
    local ok, normalized = pcall(normalize, raw)
    if not ok then return {ok=false,error=tostring(normalized)} end
    if not ready then return { ok = false, error = 'Configuracoes ainda carregando.' } end
    if saving then return {ok=false,error='Outro salvamento está em andamento.'} end
    saving=true
    local saveOk, saved, err = pcall(storage.save, normalized)
    saving=false
    if not saveOk then return {ok=false,error=tostring(saved)} end
    if not saved then return { ok = false, error = err } end

    apply(normalized)
    pr_lib.cache.set('xt-prison:settings', clone(settings))
    TriggerClientEvent('xt-prison:client:settingsUpdated', -1, clone(settings))
    return { ok = true, settings = clone(settings) }
end)

pr_lib.addCommand('prisonconfig', {
    help = 'Abre a configuração administrativa do XT Prison',
    params = {},
    restricted = false,
}, function(source)
    if source <= 0 then return end
    if not allowed(source) then
        TriggerClientEvent('xt-prison:client:notify', source, {
            title = 'XT Prison',
            description = 'Você não tem permissão para abrir esta configuração.',
            type = 'error'
        })
        return
    end
    TriggerClientEvent('xt-prison:client:openSettings', source)
end)

exports('GetSettings', function()
    return clone(settings or defaultSettings())
end)

CreateThread(function()
    while not ready do Wait(250) end
    XTPrison.log('info', 'Configurações dinâmicas carregadas.')
end)
