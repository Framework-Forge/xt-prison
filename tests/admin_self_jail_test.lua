-- Isolated command tests. Run lua55.exe tests/admin_self_jail_test.lua.
local commands, notifications, calls = {}, {}, {}
local players, admins, cops, permissions = {}, {}, {}, {}
local buckets, positions = {}, {}
local config = { EnableJailCommand = true, PoliceJobs = { 'police' }, Lifers = {} }
local menu, selected, revoke, enterResult
local utils
local vector = {}
vector.__sub = function(a, b) return setmetatable({ x = a.x - b.x }, vector) end
vector.__len = function(a) return math.abs(a.x) end
local function coords(x) return setmetatable({ x = x }, vector) end
local function check(value, message) assert(value, message) end
local function reset()
    players, admins, cops, permissions = { [10] = true }, {}, {}, {}
    buckets, positions = {}, { [10] = 0 }
    notifications, calls, menu, selected, revoke = {}, {}, nil, nil, false
    enterResult = true
end
pr_lib = {
    ace = {
        isAdminWhitelisted = function(src) return admins[src] == true end,
        isPlayerAceAllowed = function(src, permission) return permissions[src .. ':' .. permission] == true end,
    },
    framework = {
        HasPermission = function(src, permission) return permissions[src .. ':framework:' .. permission] == true end,
    },
    addCommand = function(name, _, handler) commands[name] = handler end,
    callback = {
        await = function(name, target, value)
            if name == 'xt-prison:client:jailPlayerInput' then
                menu = value
                if revoke then admins[target] = nil end
                if selected then return { selected, 1, 'minutes', 'real' } end
                return nil
            end
            calls[#calls + 1] = { name = name, target = target, value = value }
            return enterResult
        end,
    },
}
getPlayer = function(src) return players[src] and {} end
getCharName = function(src) return 'Character ' .. src end
charHasJob = function(src) return cops[src] == true end
GetPlayers = function()
    local result = {}
    for src, loaded in pairs(players) do if loaded then result[#result + 1] = tostring(src) end end
    return result
end
GetPlayerPed = function(src) return src end
GetEntityCoords = function(ped) return coords(positions[ped] or 0) end
GetPlayerRoutingBucket = function(src) return buckets[src] or 0 end
exports = function() end
locale = function(key) return key end
TriggerClientEvent = function() end
XTPrison = {
    load = function(path)
        if path == 'configs.server' then return config end
        if path == 'configs.prisonbreak' then return {} end
        if path == 'modules.server.utils' then return utils end
        error('unexpected module ' .. path)
    end,
    playerState = function() return { jailTime = 0 } end,
    notifyPlayer = function(src, value) notifications[#notifications + 1] = { src = src, value = value } end,
}
utils = dofile('modules/server/utils.lua')
pr_lib.callback.awaitClient = function(target, name, timeout, value)
    if name == 'xt-prison:client:jailPlayerInput' then check(timeout == 120000, 'form requires explicit long deadline') end
    return pr_lib.callback.await(name, target, value)
end
XTPrison.jailPlayer = function(target, sentence)
    return pr_lib.callback.await('xt-prison:client:enterJail', target, sentence)
end
XTPrison.releasePlayer = function(target)
    if not setJailTime(target, 0) then return false end
    return pr_lib.callback.await('xt-prison:client:exitJail', target, true)
end
XTPrison.actionFailure = function(src, target, action, reason)
    XTPrison.notifyPlayer(src, { type = 'error', reason = reason })
end
dofile('server/sv_commands.lua')

reset()
admins[10], selected = true, 10
commands.jail(10, {})
check(#menu == 1 and menu[1].value == 10, 'admin must see own loaded character alone')
check(#calls == 1 and calls[1].target == 10, 'admin self-jail callback')

reset()
permissions['10:xt-prison.admin'], selected = true, 10
commands.jail(10, {})
check(menu[1].value == 10 and #calls == 1, 'explicit admin ACE')

reset()
permissions['10:framework:admin'], selected = true, 10
commands.jail(10, {})
check(menu[1].value == 10 and #calls == 1, 'framework admin via bridge')

reset()
commands.jail(10, {})
check(menu == nil and #calls == 0, 'ordinary player must not open jail workflow')

reset()
cops[10] = true
commands.jail(10, {})
check(#menu == 0, 'non-admin police must not gain self-jail')
selected = 10
commands.jail(10, {})
check(#calls == 0, 'forged self-selection by non-admin police')

reset()
cops[10], players[20], positions[20], selected = true, true, 2, 20
commands.jail(10, {})
check(#menu == 1 and menu[1].value == 20 and calls[1].target == 20, 'normal nearby police workflow')

reset()
admins[10], players[20], positions[20], players[30], positions[30] = true, true, 2, true, 20
players[40], positions[40], buckets[40] = true, 1, 1
commands.jail(10, {})
check(#menu == 2 and menu[1].value == 10 and menu[2].value == 20, 'nearby and bucket filtering')

reset()
admins[10], selected, revoke = true, 10, true
commands.jail(10, {})
check(#calls == 0, 'permissions must be rechecked after dialog')

reset()
admins[10], selected, enterResult = true, 10, false
commands.jail(10, {})
check(#notifications == 1 and notifications[1].value.type == 'error', 'failed jail entry must report failure, not success')

reset()
admins[10] = true
local released
XTPrison.playerState = function() return { jailTime = 10 } end
setJailTime = function(src, amount) released = src == 10 and amount == 0; return released end
commands.unjail(10, { id = 10 })
check(released and calls[1].name == 'xt-prison:client:exitJail', 'admin must be able to release self')
print('PASS: admin whitelist/ACE/framework permissions, self-selection, police restrictions, nearby/bucket filtering, reauthorization and release')
