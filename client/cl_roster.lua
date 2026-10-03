local config = XTPrison.load 'configs.client'
local rosterZone

-- Unjail Player --
local function unjailConfirmation(info)
    local confirmation = pr_lib.AlertDialog({
        header = ('Unjail %s?'):format(info.name),
        content = ('Are you sure you want to unjail **%s**?  \nThey still have **%s Months** left.'):format(info.name, info.jailTime),
        centered = true,
        cancel = true,
    }) if confirmation == 'cancel' then return end

    local unjailed = pr_lib.callback.await('xt-prison:server:unjailPlayerByRoster', false, info.source)
    if unjailed then
        pr_lib.Notify({
            title = ('%s was released!'):format(info.name),
            type = 'success'
        })
    end
end

-- Change Player's Jail Time --
local function changeJailTime(info)
    local rules = XTPrison.settings and XTPrison.settings.sentence or {}
    local newTime = pr_lib.InputDialog(('Change Jail Time: %s'):format(info.name), {
        { type = 'number', label = 'Novo tempo', description = ('Restante: %s minutos'):format(info.jailTime), icon = 'hashtag', default = 1, min = 1, max = tonumber(rules.maxAmount) or 9999, required = true },
        { type = 'select', label = 'Unidade', default = rules.defaultUnit or 'minutes', required = true, options = {
            { label = 'Minutos', value = 'minutes' },
            { label = 'Horas', value = 'hours' },
            { label = 'Dias', value = 'days' },
        }},
        { type = 'select', label = 'Contagem', default = rules.defaultClock or 'real', required = true, options = {
            { label = 'Vida real', value = 'real' },
            { label = 'Tempo do jogo', value = 'game' },
        }},
    }) if not newTime then return end

    local sentence = { amount = tonumber(newTime[1]), unit = newTime[2], clock = newTime[3] }
    local setTime = pr_lib.callback.await('xt-prison:server:changePlayerJailTimeByRoster', false, info.source, sentence)
    if setTime then
        pr_lib.Notify({
            title = ('Changed %s\'s Jail Time!'):format(info.name),
            description = ('Nova pena: %s %s (%s)'):format(newTime[1], newTime[2], newTime[3] == 'game' and 'tempo do jogo' or 'vida real'),
            type = 'success'
        })
    end
end

local function rosterActionMenu(info)
    local actions = {
        {
            title = 'Change Jail Time',
            icon = 'fas fa-hourglass',
            onSelect = function()
                changeJailTime(info)
            end
        },
        {
            title = 'Unjail',
            icon = 'fas fa-lock-open',
            onSelect = function()
                unjailConfirmation(info)
            end
        }
    }

    pr_lib.RegisterContext({
        id = 'prisoners_roster_actions',
        title = info.name,
        menu = 'prisoners_roster',
        options = actions
    })
    pr_lib.ShowContext('prisoners_roster_actions')
end

local function openPublicRoster()
    local jailRoster = pr_lib.callback.await('xt-prison:server:getJailRoster', false)
    if not jailRoster then return end

    if not jailRoster[1] then
        jailRoster = {
            {
                title = 'No Prisoners!',
                readOnly = true
            }
        }
    else
        for x = 1, #jailRoster do
            jailRoster[x].readOnly = true
        end
    end

    pr_lib.RegisterContext({
        id = 'prisoners_public_roster',
        title = 'Jail Roster',
        options = jailRoster
    })
    pr_lib.ShowContext('prisoners_public_roster')
end

local function createRosterZone()
    if rosterZone then return end
    local zoneInfo = config.RosterLocation
    rosterZone = pr_lib.target.addSphereZone({
        name = 'xt_prison_roster',
        coords = zoneInfo.coords,
        radius = zoneInfo.radius,
        debug = zoneInfo.DebugPoly,
        drawSprite = true,
        options = {
            {
                label = 'View Prisoners Roster',
                icon = 'fas fa-clipboard-list',
                onSelect = openPublicRoster
            }
        }
    })
end

local function removeRosterZone()
    if rosterZone then pr_lib.target.removeZone(rosterZone) end
    rosterZone = nil
end

-- Open Prisoners Manageable Roster as Cop --
RegisterNetEvent('xt-prison:client:openPrivateJailRoster', function(jailRoster)
    if GetInvokingResource() then return end

    if not jailRoster[1] then
        jailRoster = {
            {
                title = 'No Prisoners!',
                readOnly = true
            }
        }
    else
        for x = 1, #jailRoster do
            jailRoster[x].onSelect = function()
                rosterActionMenu(jailRoster[x].private)
            end
        end
    end

    pr_lib.RegisterContext({
        id = 'prisoners_roster',
        title = 'Jail Roster',
        options = jailRoster
    })
    pr_lib.ShowContext('prisoners_roster')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createRosterZone()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removeRosterZone()
end)

AddEventHandler('xt-prison:client:onLoad', function()
    createRosterZone()
end)

AddEventHandler('xt-prison:client:onUnload', function()
    removeRosterZone()
end)

AddEventHandler('xt-prison:client:configurationUpdated', function()
    removeRosterZone()
    createRosterZone()
end)

