-- Run with lua55.exe from the resource directory; no live database is touched.
local function check(value, message) assert(value, message) end
local values, handlers, callbacks, packets = {}, {}, {}, {}
local identifiers = { [10] = 'CHAR_A', [20] = 'CHAR_B' }
local server = true
local cache = {
    get = function(key) return values[key] end,
    set = function(key, value) values[key] = value end,
    clear = function(key) values[key] = nil end,
    clearPrefix = function(prefix)
        for key in pairs(values) do if key:sub(1, #prefix) == prefix then values[key] = nil end end
    end,
}
IsDuplicityVersion = function() return server end
GetCurrentResourceName = function() return 'xt-prison' end
AddEventHandler = function(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
RegisterNetEvent = function(name, fn) handlers[name] = { fn } end
TriggerEvent = function(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
TriggerClientEvent = function(name, target, ...)
    packets[#packets + 1] = { name = name, target = target, args = { ... } }
end
exports = function() end
pr_lib = {
    cache = cache,
    framework = { GetIdentifier = function(src) return identifiers[src] end },
    callback = { register = function(name, fn) callbacks[name] = fn end },
}
XTPrison = {}
dofile('bridge/cache.lua')
local stateA, stateB = XTPrison.playerState(10), XTPrison.playerState(20)
stateA:set('jailTime', 50, true)
stateB:set('jailTime', 7, true)
check(stateA.jailTime == 50 and stateB.jailTime == 7, 'character isolation')
check(packets[#packets].target == 20, 'player state must never broadcast')
stateA.jailSentence = { clock = 'game', remainingMinutes = 50 }
local sentence = stateA.jailSentence
sentence.remainingMinutes = 0
check(stateA.jailSentence.remainingMinutes == 50, 'getter leaked mutable state')
XTPrison.world.PrisonTerminal_1 = { isBusy = true, lastHacker = 10 }
identifiers[10] = nil
check(XTPrison.playerState(10) == nil, 'disconnected session should not resolve normally')
check(XTPrison.playerState(10, true).jailTime == 50, 'disconnect persistence fallback')
XTPrison.clearPlayer(10, 'CHAR_A')
check(values['xt-prison:character:CHAR_A'] == nil, 'character cleanup')
check(XTPrison.world.PrisonTerminal_1.isBusy == false, 'departed terminal owner cleanup')
identifiers[10] = 'CHAR_C'
check(XTPrison.playerState(10).jailTime == 0, 'reused source inherited sentence')
XTPrison.playerState(10):set('jailTime', 12)
XTPrison.clearPlayer(10, 'CHAR_A')
check(XTPrison.playerState(10).jailTime == 12, 'old disconnect cleared replacement session')
local snapshot = callbacks['xt-prison:server:cacheSnapshot'](20)
check(snapshot.player.jailTime == 7, 'snapshot leaked another character')
local metadata = {}
pr_lib.framework.GetPlayer = function(src) return identifiers[src] and {} end
pr_lib.framework.SetPlayerMetadata = function(src, key, value)
    metadata[src] = metadata[src] or {}
    metadata[src][key] = value
end
syncJailCompatibility = function() end
dofile('bridge/server/pr_bridge.lua')
check(setJailTime(10, 25), 'framework-linked setter')
check(metadata[10].injail == 25 and XTPrison.playerState(10).jailTime == 25, 'metadata/cache alignment')
check(not setJailTime(10, 0 / 0) and not setJailTime(10, math.huge), 'nonfinite sentence')
local assigned = setJailSentence(10, { amount = 2, unit = 'hours', clock = 'real' })
check(assigned.totalMinutes == 120 and metadata[10].injail == 120, 'sentence conversion')
check(setJailTime(10, 0) and XTPrison.playerState(10).jailSentence == nil, 'release sentence cleanup')
print('PASS: character isolation, targeted sync, copy safety, disconnect and source reuse')
print('PASS: framework metadata/cache alignment, sentence conversion and release')

local savedSnapshot = snapshot
values, handlers = {}, {}
server = false
XTPrison = {}
pr_lib.callback.await = function() return savedSnapshot end
dofile('bridge/cache.lua')
check(XTPrison.refreshCache(), 'snapshot refresh')
check(XTPrison.localState.jailTime == 7, 'client hydration')
source = 0
TriggerEvent('xt-prison:client:playerCache', { jailTime = 0 }, 100)
check(XTPrison.localState.jailTime == 7, 'spoofed server event accepted')
source = 65535
TriggerEvent('xt-prison:client:playerCache', { jailTime = 9 }, 100)
TriggerEvent('xt-prison:client:playerCache', { jailTime = 1 }, 99)
check(XTPrison.localState.jailTime == 9, 'stale revision accepted')
TriggerEvent('xt-prison:client:onUnload')
check(XTPrison.localState.jailTime == 0, 'client logout cleanup')
print('PASS: client snapshots, server-event origin, packet revisions and logout')

local tables, queries = {}, {}
local files, failWrite = {}, false
LoadResourceFile=function(_,path) return files[path] end
SaveResourceFile=function(_,path,raw) if failWrite then return false end; files[path]=raw; return true end
local failedTable, record, corrupt = nil, nil, false
local timer = 0
CreateThread = function(fn) fn() end
GetGameTimer = function() return timer end
Wait = function(ms) timer = timer + ms end
GetConvar = function(_, default) return default end
json = {
    encode = function(value) return 'encoded:' .. tostring(value.value) end,
    decode = function(raw)
        if corrupt then error('bad JSON') end
        return { value = tonumber(raw:match('encoded:(%d+)')) }
    end,
}
pr_lib.activeBridges = { frameworks = 'qbx' }
pr_lib.database = {
    ready = function(fn) fn() end,
    query = function(sql, args)
        queries[#queries + 1] = sql
        local name = sql:match('CREATE TABLE IF NOT EXISTS%s+`?([%w_]+)')
        if name then
            if name == failedTable then return nil end
            tables[name] = true
            return {}
        end
        if sql:find('INFORMATION_SCHEMA.TABLES', 1, true) then
            return { { count = tables[args[1]] and 1 or 0 } }
        end
        if sql:find('INFORMATION_SCHEMA.COLUMNS', 1, true) then
            return { { count = sql:find("TABLE_NAME = 'xt_prison'", 1, true) and 1 or 0 } }
        end
        if sql:find('SELECT data FROM xt_prison_settings', 1, true) then
            return record and { { data = record } } or {}
        end
        error('unexpected query: ' .. sql)
    end,
    execute = function(sql, args)
        if sql:find('UPDATE xt_prison_settings',1,true) then record=args[1]
        elseif sql:find('DELETE FROM xt_prison_settings',1,true) then record=nil
        else record=args[2] end
        return 1
    end,
    scalar = function() return record end,
}
XTPrison.log = function() end
local database = dofile('modules/server/db.lua')
check(database.awaitReady(), 'schema readiness')
check(tables.xt_prison and tables.xt_prison_items and tables.xt_prison_settings, 'missing table')
for _, sql in ipairs(queries) do check(not sql:find('DROP COLUMN', 1, true), 'destructive migration') end
XTPrison.load = function() return database end
local storage = dofile('modules/server/settings_storage.lua')
local loaded, err = storage.load()
check(loaded == nil and err == nil and storage.writable, 'new settings storage')
check(storage.save({ value = 42 }), 'default settings insertion')
loaded = storage.load()
check(loaded.value == 42, 'settings reload')
check(files['data/settings.json']==record,'JSON snapshot mismatch')
failWrite=true
check(not storage.save({value=43}),'failed JSON write accepted')
check(record=='encoded:42','failed JSON write did not roll back database')
failWrite=false
corrupt = true
local brokenStorage = dofile('modules/server/settings_storage.lua')
loaded, err = brokenStorage.load()
check(loaded == nil and err and not brokenStorage.writable, 'corrupt settings overwrite prevention')
check(not brokenStorage.save({ value = 0 }), 'corrupt storage accepted write')
corrupt = false
failedTable = 'xt_prison_settings'
database = dofile('modules/server/db.lua')
check(not database.awaitReady(), 'failed installation reported as ready')
local unavailable = dofile('modules/server/settings_storage.lua')
loaded, err = unavailable.load()
check(loaded == nil and err and not unavailable.writable, 'failed schema must block saves')
print('PASS: three-table installation, readiness, settings persistence, corruption and schema failure')
