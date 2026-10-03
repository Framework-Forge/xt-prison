-- Resource-owned state, linked to the framework character through PR Bridge.
local cache = pr_lib.cache
local prefix = 'xt-prison:'
local server = IsDuplicityVersion()
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function facade(key, changed, defaults)
    local methods = {}
    function methods:get(name)
        local record = cache.get(key) or {}
        local value = record[name]
        if value == nil then value = defaults and defaults[name] end
        return copy(value)
    end
    function methods:set(name, value)
        local record = copy(cache.get(key) or {})
        record[name] = copy(value)
        cache.set(key, record)
        if changed then changed(copy(record)) end
    end
    return setmetatable({}, {
        __index = function(_, name) return methods[name] or methods:get(name) end,
        __newindex = function(_, name, value) methods:set(name, value) end,
    })
end

XTPrison.world = facade(prefix .. 'world', server and function(record)
    local revision = (cache.get(prefix .. 'worldRevision') or 0) + 1
    cache.set(prefix .. 'worldRevision', revision)
    TriggerClientEvent('xt-prison:client:worldCache', -1, record, revision)
end or nil, { copCount = 0, prisonAlarms = false })

if server then
    function XTPrison.playerState(src, disconnected)
        src = tonumber(src)
        if not src then return nil end
        local identifier = pr_lib.framework.GetIdentifier(src)
        local binding = prefix .. 'binding:' .. src
        if not identifier and disconnected then identifier = cache.get(binding) end
        if not identifier then return nil end
        cache.set(binding, identifier)
        local key = prefix .. 'character:' .. identifier
        return facade(key, function(record)
            local revision = (cache.get(prefix .. 'playerRevision') or 0) + 1
            cache.set(prefix .. 'playerRevision', revision)
            record.xtprison_identifier = identifier
            TriggerClientEvent('xt-prison:client:playerCache', src, record, revision)
        end, { jailTime = 0, xtprison_identifier = identifier })
    end

    function XTPrison.clearPlayer(src, expectedIdentifier)
        local binding = prefix .. 'binding:' .. tostring(src)
        local identifier = cache.get(binding)
        if expectedIdentifier and identifier ~= expectedIdentifier then return end
        if identifier then cache.clear(prefix .. 'character:' .. identifier) end
        cache.clear(binding)
        cache.clear(prefix .. 'cooldown:' .. tostring(src))
        -- Free hacking terminals reserved by a departed character/session.
        for name, terminal in pairs(cache.get(prefix .. 'world') or {}) do
            if type(terminal) == 'table' and terminal.lastHacker == tonumber(src) then
                terminal.isBusy, terminal.lastHacker = false, nil
                XTPrison.world[name] = terminal
            end
        end
    end

    pr_lib.callback.register('xt-prison:server:cacheSnapshot', function(src)
        local state = XTPrison.playerState(src)
        return {
            world = copy(cache.get(prefix .. 'world') or {}),
            revision = cache.get(prefix .. 'worldRevision') or 0,
            playerRevision = cache.get(prefix .. 'playerRevision') or 0,
            player = state and {
                jailTime = state.jailTime, jailSentence = state.jailSentence,
                xtprison_identifier = state.xtprison_identifier,
            } or {},
        }
    end)
else
    XTPrison.localState = facade(prefix .. 'self', nil, { jailTime = 0 })
    local revision = -1
    local playerRevision = -1
    local lifecycle, active = 0, true
    local function applyPlayer(record, version)
        if type(record) ~= 'table' or type(version) ~= 'number' or version <= playerRevision then return end
        playerRevision = version
        cache.set(prefix .. 'self', copy(record))
    end
    local function applyWorld(record, version)
        if type(record) ~= 'table' or type(version) ~= 'number' or version <= revision then return end
        revision = version
        local previous = XTPrison.world.prisonAlarms
        local previousEscapes=XTPrison.world.escapeAlarms or {}
        cache.set(prefix .. 'world', copy(record))
        if previous ~= XTPrison.world.prisonAlarms then
            TriggerEvent('xt-prison:client:alarmCacheChanged', XTPrison.world.prisonAlarms)
        end
        local nextEscapes=XTPrison.world.escapeAlarms or {}
        local changed=false
        for key,value in pairs(previousEscapes) do if nextEscapes[key]~=value then changed=true;break end end
        if not changed then for key,value in pairs(nextEscapes) do if previousEscapes[key]~=value then changed=true;break end end end
        if changed then TriggerEvent('xt-prison:client:escapeAlarmCacheChanged',nextEscapes) end
    end
    RegisterNetEvent('xt-prison:client:worldCache', function(record, version)
        if source ~= 65535 then return end
        applyWorld(record, version)
    end)
    RegisterNetEvent('xt-prison:client:playerCache', function(record, version)
        if source ~= 65535 or not active then return end
        applyPlayer(record, version)
    end)
    function XTPrison.refreshCache()
        local generation = lifecycle
        local payload = pr_lib.callback.await('xt-prison:server:cacheSnapshot', false)
        if type(payload) ~= 'table' or not active or generation ~= lifecycle then return false end
        applyWorld(payload.world, payload.revision)
        applyPlayer(payload.player, payload.playerRevision)
        return true
    end
    AddEventHandler('xt-prison:client:onUnload', function()
        lifecycle, active = lifecycle + 1, false
        cache.clear(prefix .. 'self')
    end)
    AddEventHandler('xt-prison:client:onLoad', function()
        lifecycle, active = lifecycle + 1, true
        cache.clear(prefix .. 'self')
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Defer server cleanup until persistence/door-reset handlers have run.
    if not server then cache.clearPrefix(prefix) end
end)

exports('GetPrisonCache', function(src)
    local state = server and XTPrison.playerState(src) or XTPrison.localState
    return state and { jailTime = state.jailTime, jailSentence = state.jailSentence,
        xtprison_identifier = state.xtprison_identifier } or nil
end)
