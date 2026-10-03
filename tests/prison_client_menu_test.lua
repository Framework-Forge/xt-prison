local now, state, sent, threads = 0, {}, {}, {}
local config = {
    RemoveJob = true, EnablePrisonOutfits = false, DebugPoly = false,
    Spawns = { { coords = { x = 1, y = 2, z = 50, w = 10 }, emote = 'idle' } },
    EnterPrisonAlert = { enable = false },
    playJailSound = function() end, Emote = function() end,
    CheckOut = { coords = {}, size = {}, rotation = 0 },
}
local vec = {}
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vec3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end
local position, fadeOut, fadeIn, removed = vec3(0, 0, 0), nil, nil, true
PlayerPedId = function() return 1 end
SetEntityCoords = function(_, x, y, z) position = vec3(x, y, z) end
SetEntityHeading = function() end
GetEntityCoords = function() return position end
GetGameTimer = function() return now end
Wait = function(ms) now = now + math.max(1, ms) end
DoScreenFadeOut = function(ms) fadeOut = now + ms end
IsScreenFadedOut = function() return now >= fadeOut end
DoScreenFadeIn = function(ms) fadeIn = now + ms end
IsScreenFadedIn = function() return now >= fadeIn end
FreezeEntityPosition = function() end
RequestCollisionAtCoord = function() end
HasCollisionLoadedAroundEntity = function() return now >= 10000 end
GetResourceState = function() return 'missing' end
CreateThread = function(fn) threads[#threads + 1] = fn end
TriggerServerEvent = function(name) sent[#sent + 1] = name end
locale = function(key) return key end
local methods = { set = function(_, key, value) state[key] = value end }
local facade = setmetatable({}, { __index = function(_, key) return methods[key] or state[key] end })
XTPrison = {
    localState = facade,
    load = function(path)
        if path == 'configs.client' then return config end
        return {}
    end,
}
pr_lib = {
    callback = { await = function(name)
        if name == 'xt-prison:server:setJailStatus' then return { remainingMinutes = 5, tickSeconds = 60 } end
        if name == 'xt-prison:server:removeJob' then return removed, not removed and 'job_removal_failed' or nil end
        return false
    end },
    target = { addBoxZone = function() return 1 end },
    Notify = function() end,
}
state = { jailTime = 5 }
local prison = dofile('modules/client/prison.lua')
removed = false
local ok, reason = prison.enterPrison({ amount = 5 })
assert(not ok and reason == 'job_removal_failed' and #sent == 0, 'job failure must return its cause before inventory changes')
removed = true
assert(prison.enterPrison({ amount = 5 }), 'client teleport flow failed')
assert(now >= 12000 and position.x == 1 and position.y == 2, 'entry duration/position regression')
assert(sent[#sent] == 'xt-prison:server:removeItems', 'inventory should change after successful positioning')
local before = now
assert(prison.enterPrison({ amount = 8 }) and now == before, 'already jailed player should not repeat teleport/fades')
print('PASS: actual client entry takes over 10 seconds, teleports, reports job failure and does not repeat entry')

local resourceRoot = 'E:/[FIVEM]/Forge-Core/resources/[forge]/[forge-scripts]/forge-core/'
local payload, context
ForgeCore = { Client = { Menu = {}, MenuShared = {
    t = function(key) return key end,
    awaitServer = function() return true, payload end,
    showContext = function(value) context = value end,
    notifyFailure = function() error('unexpected menu failure') end,
} } }
PR = { Player = { Callbacks = { getInfo = 'info' } }, PlayerManagement = { Callbacks = { details = 'details' } } }
dofile(resourceRoot .. 'client/menu/menu_prison.lua')
dofile(resourceRoot .. 'client/menu/menu_player.lua')
dofile(resourceRoot .. 'client/menu/menu_players.lua')
local function find(title)
    for _, option in ipairs(context.options) do if option.title == title then return option end end
end
payload = { prison = { enabled = true, jailed = true, remainingMinutes = 5, clock = 'real' } }
ForgeCore.Client.Menu.openPlayerMenu()
assert(find('prison.title'), 'F9 must show active own sentence')
payload.prison = nil
ForgeCore.Client.Menu.openPlayerMenu()
assert(not find('prison.title'), 'F9 must hide prison when provider unavailable')
payload = {
    source = 1, citizenid = 'CHAR_A', name = 'Player', metadata = {}, money = {},
    whitelist = {}, vip = { tier = 'standard', label = 'Standard', expiresAtFormatted = '-' },
    prison = { enabled = true, jailed = true, remainingMinutes = 5, clock = 'real' },
}
ForgeCore.Client.Menu.openManagedPlayer(1)
assert(find('prison.set') and find('prison.release'), 'management actions missing')
assert(context.options[1].description:find('prison.title', 1, true), 'main player data must include sentence')
payload.prison = nil
ForgeCore.Client.Menu.openManagedPlayer(1)
assert(not find('prison.set') and not find('prison.release'), 'management must hide unavailable provider')
print('PASS: actual Forge F9/management menus include prison data/actions only with active provider')
