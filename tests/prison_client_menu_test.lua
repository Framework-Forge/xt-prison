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
DoesBlipExist = function() return false end
CreateThread = function(fn) threads[#threads + 1] = fn end
TriggerServerEvent = function(name) sent[#sent + 1] = name end
locale = function(key) return key end
local methods = { set = function(_, key, value) state[key] = value end }
local facade = setmetatable({}, { __index = function(_, key) return methods[key] or state[key] end })
XTPrison = {
    localState = facade,
    load = function(path)
        if path == 'configs.client' then return config end
        if path == 'configs.prisonbreak' then return {Center=vec3(1,2,50),Radius=100} end
        if path == 'modules.client.prisonbreak' then return {removeBlip=function() end,removeHackZones=function() end} end
        return {}
    end,
}
pr_lib = {
    callback = { await = function(name)
        if name == 'xt-prison:server:setJailStatus' then return { remainingMinutes = 5, tickSeconds = 60 } end
        if name == 'xt-prison:server:removeJob' then return removed, not removed and 'job_removal_failed' or nil end
        return false
    end },
    target = { addBoxZone = function() return 1 end, removeZone = function() end },
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
position=vec3(1000,1000,50)
assert(prison.enterPrison({amount=8}) and position.x==1 and position.y==2,
    'An active prisoner outside the boundary must be repositioned instead of skipping entry')
print('PASS: actual client entry takes over 10 seconds, teleports, reports job failure and does not repeat entry')

config.EnablePrisonOutfits=true
local outfit={}
for _,name in ipairs({'mask','arms','pants','shoes','accessories','shirt','jacket'}) do outfit[name]={item=5,texture=1} end
config.PrisonOufits={male=outfit,female=outfit}
local clothes,writes={},0
GetHashKey=function(model) return model end
IsPedModel=function() return true end
SetPedComponentVariation=function(_,slot,item,texture,palette) assert(palette==0,'Native must receive the palette argument');clothes[slot]={item,texture};writes=writes+1 end
GetPedDrawableVariation=function(_,slot) return clothes[slot] and clothes[slot][1] or 0 end
GetPedTextureVariation=function(_,slot) return clothes[slot] and clothes[slot][2] or 0 end
state.prisonStatus='jailed'
before=now
assert(prison.enterPrison(5) and writes==7 and now==before,'Already inside prison must reapply uniform without repeating teleport')
prison.reconcilePrisonUniform()
local originalWait=Wait
local steps=0
Wait=function(ms)
    originalWait(ms);steps=steps+1
    if steps==1 then now=now+20000;clothes={} end -- Appearance can overwrite the uniform beyond the former 15s window.
    if steps==3 then state.prisonStatus='fugitive' end
end
threads[#threads]()
assert(writes==14,'Login reconciliation must repair the saved civilian outfit and stop upon escape')
assert(not prison.applyPrisonUniform() and writes==14,'Fugitive must never receive a prison uniform')
state.prisonStatus='free'
assert(not prison.applyPrisonUniform() and writes==14,'Free character must never receive a prison uniform')
state.prisonStatus='jailed'
prison.reconcilePrisonUniform()
local pending=threads[#threads]
prison.prisonCleanup()
pending()
assert(writes==14,'Logout must invalidate pending uniform reconciliation')
Wait=originalWait
local modelReadyAt=now+300
local positionCalls=0
IsPedModel=function() return now>=modelReadyAt end
local originalCoords=SetEntityCoords
SetEntityCoords=function(...)
    assert(now>=modelReadyAt,'Never teleport Michael before the real character model is ready')
    positionCalls=positionCalls+1
    originalCoords(...)
end
position=vec3(1000,1000,50)
assert(prison.enterPrison(5) and positionCalls>0 and writes==21,'Arrival at a prison entry point must dress the final ped')
SetEntityCoords=originalCoords
state.prisonStatus='fugitive'
local beforeFailure=writes
IsPedModel=function() return false end
local entered,reason=prison.enterPrison(5)
assert(not entered and reason=='sentence_changed' and writes==beforeFailure,'A fugitive must not wait for a prison model or receive an outfit')
config.EnablePrisonOutfits=false
print('PASS: reconnect uniform, delayed civilian appearance correction, fugitive/free exclusion and logout cancellation')

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
assert(find('menu.multijob.title').disabled, 'Jailed character must not open My Jobs')
payload.prison = {enabled=true,jailed=false,fugitive=true,status='fugitive',remainingMinutes=5}
ForgeCore.Client.Menu.openPlayerMenu()
assert(find('prison.title') and not find('menu.multijob.title').disabled,'Fugitive must keep prison status and regain job selection')
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
