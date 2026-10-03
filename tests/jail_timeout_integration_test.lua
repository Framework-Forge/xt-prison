-- Deterministic reproduction using the actual PR Bridge callback implementation.
local root = 'E:/[FIVEM]/Forge-Core/resources/'
local now, timers, events = 0, {}, {}
GetCurrentResourceName = function() return 'xt-prison' end
GetGameTimer = function() return now end
GetConvarInt = function(_, default) return default end
GetPlayerName = function() return 'Player' end
RegisterNetEvent = function(name, fn) events[name] = fn end
AddEventHandler = function() end
SetTimeout = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end
promise = { new = function() return { resolve = function(self, value) self.value = value end } end }
Citizen = { Await = function(p)
    while not p.value do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local item = table.remove(timers, 1)
        assert(item, 'missing response')
        now = item.at
        item.fn()
    end
    return p.value
end }
TriggerClientEvent = function(_, target, requestId)
    SetTimeout(25000, function()
        source = target
        events['pr_bridge:callback:response:xt-prison'](requestId, { __prCallback = true, ok = true }, { 1, 5, 'minutes', 'real' })
    end)
end
local callback = dofile(root .. '[forge]/[forge-scripts]/pr_bridge/bridge/callback/secure_server.lua')
local value, reason = callback.await('test:dialog', 1)
assert(value == nil and reason == 'timeout' and now == 10000, 'original 10s timeout not reproduced')
now, timers = 0, {}
value = callback.awaitClient(1, 'test:dialog', 120000)
assert(value[2] == 5 and now == 25000, 'explicit form deadline failed')
print('PASS: real bridge reproduces discarded 25-second form at default 10s; explicit 120s deadline accepts it')

-- The actual action service: commit, rollback, explicit entry/release waits.
local state, saved, metadata, packets = {}, {}, {}, {}
local enterResult, enterReason, canPersist = true, nil, true
local methods = {}
function methods:set(key, val) state[key] = val end
local facade = setmetatable({}, { __index = function(_, key) return methods[key] or state[key] end })
local function reset()
    state = { jailTime = 0 }
    saved, metadata, packets = {}, {}, {}
    enterResult, enterReason, canPersist = true, nil, true
end
getCharID = function(src) return src == 1 and 'CHAR_A' end
getPlayer = function(src) return src == 1 and {} end
setJailTime = function(_, amount) state.jailTime = amount; metadata.injail = amount; if amount == 0 then state.jailSentence = nil end; return true end
setJailSentence = function(src, value)
    local amount = type(value) == 'table' and value.amount or value
    setJailTime(src, amount)
    state.jailSentence = { amount = amount, remainingMinutes = amount, unit = 'minutes', clock = 'real', endAt = os.time() + amount * 60 }
    return state.jailSentence
end
json = { encode = function() return 'sentence' end }
pr_lib = {
    addExports = function() end,
    framework = { GetPlayerJob = function() return { name = 'unemployed' } end },
    cache = {
        get = function(key) return saved[key] end,
        set = function(key, value) saved[key] = value; if key == 'xt-prison:character:CHAR_A' then state = value end end,
        clear = function(key) saved[key] = nil end,
    },
    database = { insert = function() return 0 end },
    callback = { awaitClient = function(_, name, timeout)
        assert(timeout == 45000, 'entry/release must have bounded 45s deadline')
        packets[#packets + 1] = name
        return enterResult, enterReason
    end },
}
XTPrison = {
    load = function() return { awaitReady = function() return true end, UPDATE_JAILTIME = 'persist' } end,
    persistPlayer = function() return canPersist end,
    playerState = function() return facade end,
    log = function() end,
    notifyPlayer = function() end,
}
dofile('server/sv_actions.lua')
reset()
assert(XTPrison.jailPlayer(1, { amount = 5 }))
assert(state.jailTime == 5 and metadata.injail == 5 and packets[1] == 'xt-prison:client:enterJail', 'commit failed')
assert(XTPrison.prisonStatus(1).remainingMinutes == 5, 'status failed')
assert(XTPrison.releasePlayer(1) and state.jailTime == 0 and metadata.injail == 0, 'release failed')
reset()
enterResult, enterReason = false, 'spawn_timeout'
local success, errorCode = XTPrison.jailPlayer(1, { amount = 5 })
assert(not success and errorCode == 'spawn_timeout' and state.jailTime == 0 and metadata.injail == 0, 'failed entry not rolled back')
assert(not saved['xt-prison:action:CHAR_A'], 'action lock leaked')
reset()
canPersist = false
assert(not XTPrison.jailPlayer(1, { amount = 5 }) and #packets == 0 and state.jailTime == 0, 'persistence failure should prevent entry')
assert(not XTPrison.jailPlayer(1, { amount = 0 }), 'invalid amount accepted')
print('PASS: prison action commit/release, explicit deadlines, failed-entry rollback and persistence failure')

-- Actual optional provider and Forge server permission boundary.
local started, admin, providerCalls = true, true, 0
GetResourceState = function() return started and 'started' or 'stopped' end
exports = { ['xt-prison'] = {
    GetPrisonStatus = function(_, src) return XTPrison.prisonStatus(src) end,
    JailPlayer = function(_, src, sentence) providerCalls = providerCalls + 1; return XTPrison.jailPlayer(src, sentence) end,
    ReleasePlayer = function(_, src) providerCalls = providerCalls + 1; return XTPrison.releasePlayer(src) end,
} }
local provider = dofile(root .. '[forge]/[forge-scripts]/pr_bridge/bridge/prison/server.lua')
pr_lib.load = function() return provider end
pr_lib.framework.GetPlayer = getPlayer
ForgeCore = { JobService = { canManage = function() return admin end } }
dofile(root .. '[forge]/[forge-scripts]/forge-core/server/player/prison.lua')
reset()
assert(ForgeCore.PrisonService.setSentence(1, 1, { amount = 5 }), 'authorized Forge action')
admin = false
local before = providerCalls
assert(not ForgeCore.PrisonService.setSentence(2, 1, { amount = 5 }) and before == providerCalls, 'unauthorized Forge action reached provider')
started = false
assert(ForgeCore.PrisonService.status(1) == nil, 'stopped prison should not produce menu data')
admin = true
assert(not ForgeCore.PrisonService.release(1, 1), 'stopped prison accepted action')
print('PASS: PR Bridge prison adapter, Forge authorization and stopped-provider handling')
