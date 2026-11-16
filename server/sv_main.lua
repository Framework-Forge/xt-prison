local db = XTPrison.load 'modules.server.db'
local config = XTPrison.load 'configs.server'
local prisonBreakcfg = XTPrison.load 'configs.prisonbreak'
local utils = XTPrison.load 'modules.server.utils'
local inventory = pr_lib.inventory
local database = pr_lib.database
local globalState = XTPrison.world

local function normalizeItems(items)
    local result = {}
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and (item.name or item.item) then
            result[#result + 1] = {
                name = item.name or item.item,
                count = tonumber(item.count or item.amount or item.quantity) or 1,
                metadata = item.metadata or item.info or {},
                slot = item.slot,
            }
        end
    end
    return result
end

local function notify(source, data)
    XTPrison.notifyPlayer(source, data)
end

local function savePlayerJailTime(source)
    local state = XTPrison.playerState(source, true)
    local jailTime = state and state.jailTime or 0
    local citizenId = getCharID(source) or (state and state.xtprison_identifier)
    if not state or not pr_lib.cache.get('xt-prison:character:' .. tostring(citizenId)) then return false end
    if not citizenId then
        XTPrison.log('warn', 'player core identifier not found, not saving jailtime')
        return false
    end

    local sentence = state and state.jailSentence
    if not db.awaitReady() then return false end
    if not state.prisonLoaded then return false end
    local written = database.insert(db.UPDATE_JAILTIME, { citizenId, jailTime, sentence and json.encode(sentence) or nil,
        state.prisonStatus or (jailTime > 0 and 'jailed' or 'free') })
    if written == nil or written == false then
        XTPrison.log('error', ('Falha ao salvar pena de %s.'):format(citizenId))
        return false
    end
    return true
end

XTPrison.persistPlayer = savePlayerJailTime

local function loadPlayerJailTime(source)
    local citizenId = getCharID(source)
    if not citizenId then return 0 end
    local cached = pr_lib.cache.get('xt-prison:character:' .. citizenId)
    if cached and cached.prisonLoaded then return cached.prisonStatus == 'fugitive' and 0 or tonumber(cached.jailTime) or 0 end
    local available, err = db.awaitReady()
    if not available then XTPrison.log('error', err); return nil end
    local rows = database.query(db.LOAD_JAILTIME, { citizenId })
    if type(rows) ~= 'table' then return nil end
    if getCharID(source) ~= citizenId then return nil end
    cached = pr_lib.cache.get('xt-prison:character:' .. citizenId)
    if cached and cached.prisonLoaded then return cached.prisonStatus == 'fugitive' and 0 or tonumber(cached.jailTime) or 0 end
    local row = rows[1] or {}
    local decoded, sentence = pcall(json.decode, row.sentence or 'null')
    if not decoded or (sentence ~= nil and type(sentence) ~= 'table') then
        XTPrison.log('error', 'Dados da pena invalidos; registro preservado.')
        return nil
    end
    local jailTime = tonumber(row.jailtime) or 0
    if not rows[1] and pr_lib.framework.GetPlayerMetadata then
        jailTime = tonumber(pr_lib.framework.GetPlayerMetadata(source, 'injail')) or 0
    end
    local status = row.status == 'fugitive' and 'fugitive' or (jailTime > 0 and 'jailed' or 'free')
    if status ~= 'fugitive' and sentence and sentence.clock == 'real' and sentence.endAt then
        jailTime = math.max(0, math.ceil((tonumber(sentence.endAt) - os.time()) / 60))
        sentence.remainingMinutes = jailTime
    elseif status ~= 'fugitive' and sentence and sentence.clock == 'game' then
        sentence.nextTickAt = os.time() + math.max(1, tonumber(sentence.tickSeconds) or 2)
        sentence.remainingMinutes = jailTime
    end
    if status ~= 'fugitive' and jailTime <= 0 then status = 'free' end
    if not setJailTime(source, jailTime, status) then return nil end
    if sentence and jailTime > 0 then XTPrison.playerState(source):set('jailSentence', sentence, true) end
    return status == 'fugitive' and 0 or jailTime
end

XTPrison.ensureLoaded = function(src) return loadPlayerJailTime(src) ~= nil end

pr_lib.callback.register('xt-prison:server:initJailTime', function(source)
    return loadPlayerJailTime(source)
end)

RegisterNetEvent('xt-prison:server:saveJailTime', function()
    savePlayerJailTime(source)
end)

pr_lib.callback.register('xt-prison:server:removeJob', function(source)
    if charHasJob(source, config.UnemployedJobName) then return true end
    local removed, reason = setCharJob(source, config.UnemployedJobName)
    if not removed then return false, type(reason) == 'table' and reason.code or reason or 'job_removal_failed' end

    notify(source, {
        title = locale('notify.lost_job'),
        icon = 'fas fa-ban',
        type = 'error'
    })
    return true
end)

RegisterNetEvent('xt-prison:server:removeItems', function()
    local source = source
    local citizenId = getCharID(source)
    if not citizenId then return end

    local existing = database.scalar(db.GET_ITEMS, { citizenId })
    local existingItems = json.decode(existing or '[]') or {}
    if next(existingItems) then return end

    local playerItems = normalizeItems(inventory.GetInventoryItems(source))
    if not next(playerItems) then return end

    database.insert(db.CONFISCATE_ITEMS, { citizenId, json.encode(playerItems) })
    if inventory.ClearInventory(source) == false then
        database.execute(db.CLEAR_CONFISCATED_ITEMS, { citizenId })
        XTPrison.log('error', ('failed to clear inventory for %s'):format(citizenId))
        return
    end

    notify(source, {
        title = locale('notify.confiscated'),
        icon = 'fas fa-trash',
        type = 'error'
    })
end)

RegisterNetEvent('xt-prison:server:returnItems', function()
    local source = source
    local citizenId = getCharID(source)
    if not citizenId then return end

    local player = getPlayer(source)
    if not player or (tonumber(XTPrison.playerState(source).jailTime) or 0) > 0 then
        utils.banPlayer(source, citizenId)
        return
    end

    local encoded = database.scalar(db.GET_ITEMS, { citizenId })
    local confiscatedItems = normalizeItems(json.decode(encoded or '[]') or {})
    if not next(confiscatedItems) then return end

    local prisonItems = normalizeItems(inventory.GetInventoryItems(source))
    if inventory.ClearInventory(source) == false then
        XTPrison.log('error', ('failed to clear prison inventory for %s'):format(citizenId))
        return
    end

    Wait(100)
    local restoreFailed = false
    for _, item in ipairs(confiscatedItems) do
        if not inventory.AddItem(source, item.name, item.count, item.metadata, item.slot) then
            restoreFailed = true
            XTPrison.log('error', ('failed to restore %sx %s for %s'):format(item.count, item.name, citizenId))
        end
    end

    if not restoreFailed then
        database.execute(db.CLEAR_CONFISCATED_ITEMS, { citizenId })
    end

    for _, item in ipairs(prisonItems) do
        if config.AllowedToKeepItems[item.name] then
            inventory.AddItem(source, item.name, item.count, item.metadata)
        end
    end

    notify(source, {
        title = locale('notify.returned_items'),
        description = restoreFailed and 'Alguns itens não puderam ser restaurados. O registro foi preservado para nova tentativa.' or nil,
        icon = 'fas fa-hand-holding-heart',
        type = restoreFailed and 'error' or 'success'
    })
end)

pr_lib.callback.register('xt-prison:server:setJailStatus', function(source, setTime)
    local player = getPlayer(source)
    if not player then return false end

    local state = XTPrison.playerState(source)
    if not state or state.prisonStatus ~= 'jailed' or state.jailTime <= 0 then return false, 'no_sentence' end
    return state.jailSentence or { remainingMinutes = state.jailTime, tickSeconds = 60 }
end)

pr_lib.callback.register('xt-prison:server:tickJailTime', function(source)
    local player = getPlayer(source)
    if not player then return 0 end
    local state = XTPrison.playerState(source)
    local sentence = state.jailSentence
    local remaining = tonumber(state.jailTime) or 0
    if state.prisonStatus ~= 'jailed' then return 0 end
    if remaining <= 0 then return 0 end

    if type(sentence) == 'table' and sentence.clock == 'real' and sentence.endAt then
        remaining = math.max(0, math.ceil((tonumber(sentence.endAt) - os.time()) / 60))
    elseif type(sentence) == 'table' and sentence.clock == 'game' then
        local now = os.time()
        local tickSeconds = math.max(1, tonumber(sentence.tickSeconds) or 2)
        local nextTickAt = tonumber(sentence.nextTickAt) or now
        if now >= nextTickAt then
            local elapsedTicks = math.max(1, math.floor((now - nextTickAt) / tickSeconds) + 1)
            remaining = math.max(0, remaining - elapsedTicks)
            sentence.nextTickAt = nextTickAt + elapsedTicks * tickSeconds
        end
    else
        remaining = math.max(0, remaining - 1)
    end

    if type(sentence) == 'table' then
        sentence.remainingMinutes = remaining
        state:set('jailSentence', sentence, true)
    end
    setJailTime(source, remaining)
    savePlayerJailTime(source)
    return remaining
end)

pr_lib.callback.register('xt-prison:server:liferCheck', function(source)
    return utils.liferCheck(source)
end)

pr_lib.callback.register('xt-prison:server:receiveCanteenMeal', function(source)
    local ped=GetPlayerPed(source)
    if ped==0 then return false end
    local coords=GetEntityCoords(ped)
    local nearby=false
    for _,npc in ipairs(XTPrison.settings and XTPrison.settings.npcs and XTPrison.settings.npcs.canteen or {}) do
        local p=npc.coords;local dx,dy,dz=coords.x-p.x,coords.y-p.y,coords.z-p.z
        if dx*dx+dy*dy+dz*dz<16 then nearby=true;break end
    end
    if not nearby then return false end
    local key='xt-prison:meal:'..source
    if pr_lib.cache.get(key) then return false end
    pr_lib.cache.set(key,true,5000)
    local food = config.CanteenMeal.food
    local drink = config.CanteenMeal.drink
    if not inventory.AddItem(source, food.item, food.count) then return false end

    if not inventory.AddItem(source, drink.item, drink.count) then
        inventory.RemoveItem(source, food.item, food.count)
        return false
    end

    return true
end)

pr_lib.callback.register('xt-prison:server:checkJailTime', function(source)
    local key = 'xt-prison:cooldown:' .. source
    if pr_lib.cache.get(key) then
        notify(source, {
            title = locale('notify.wait_before_check'),
            icon = 'fas fa-hourglass-half',
            type = 'error'
        })
        return
    end

    pr_lib.cache.set(key, true, 5000)

    return utils.checkJailTime(source)
end)

local function updateCopCount()
    local count = 0
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        if playerSource and getPlayer(playerSource) then
            for _, job in ipairs(config.PoliceJobs) do
                if charHasJob(playerSource, job) then
                    count = count + 1
                    break
                end
            end
        end
    end
    globalState.copCount = count
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if prisonBreakcfg.MinimumPolice == 0 then
        globalState.copCount = 0
        return
    end

    updateCopCount()
    SetInterval(updateCopCount, 120000)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = pr_lib.cache.get('xt-prison:binding:' .. src)
    savePlayerJailTime(src)
    XTPrison.clearPlayer(src, identifier)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src) or source
    local identifier = pr_lib.cache.get('xt-prison:binding:' .. src)
    savePlayerJailTime(src)
    XTPrison.clearPlayer(src, identifier)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, src in ipairs(GetPlayers()) do savePlayerJailTime(tonumber(src)) end
end)


