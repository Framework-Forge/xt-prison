local playerState           = XTPrison.localState
local config                = XTPrison.load 'configs.client'
local prisonBreakcfg        = XTPrison.load 'configs.prisonbreak'
local prisonBreakModules    = XTPrison.load 'modules.client.prisonbreak'
local utils                 = XTPrison.load 'modules.client.utils'

local inJail = false
local enteringPrison = false
local uniformRevision = 0

local mainBlip
local PrisonZone
local CheckOutZone

local prisonModules = {}

local function pointInPolygon(coords, points)
    local inside = false
    local previous = #points
    for index = 1, #points do
        local currentPoint = points[index]
        local previousPoint = points[previous]
        local intersects = ((currentPoint.y > coords.y) ~= (previousPoint.y > coords.y))
            and (coords.x < (previousPoint.x - currentPoint.x) * (coords.y - currentPoint.y)
                / ((previousPoint.y - currentPoint.y) + 0.0000001) + currentPoint.x)
        if intersects then inside = not inside end
        previous = index
    end
    return inside
end

local function isInsidePrison(coords)
    local boundary = prisonBreakcfg.Boundary
    if type(boundary) == 'table' and boundary.shape == 'poly' and type(boundary.points) == 'table' and #boundary.points >= 3 then
        local minZ = tonumber(boundary.minZ) or -1000.0
        local maxZ = tonumber(boundary.maxZ) or 1000.0
        return coords.z >= minZ and coords.z <= maxZ and pointInPolygon(coords, boundary.points)
    end
    return #(coords - prisonBreakcfg.Center) <= prisonBreakcfg.Radius
end

-- Set Jail Time --
function prisonModules.setJailTime(jailTime)
    if playerState.jailTime == jailTime then
        return true
    end

    playerState:set('jailTime', jailTime, true)

    return (playerState.jailTime == jailTime)
end

-- Create Checkout Location --
function prisonModules.createCheckoutLocation()
    if GetResourceState('xt-prisonjobs') == 'started' then return end
    if config.CheckOut.enabled == false then return end

    local checkoutInfo = config.CheckOut
    CheckOutZone = pr_lib.target.addBoxZone({
        name = 'xt_prison_checkout',
        coords = checkoutInfo.coords,
        size = checkoutInfo.size,
        rotation = checkoutInfo.rotation,
        debug = config.DebugPoly,
        drawSprite = true,
        options = {{
            name = 'xt_prison_check_time',
            label = locale('input.check_time'),
            icon = 'fas fa-hourglass-start',
            onSelect = function()
                local timeLeft = pr_lib.callback.await('xt-prison:server:checkJailTime', false)
                if timeLeft and timeLeft <= 0 then prisonModules.exitPrison(true) end
            end
        }}
    })
end

-- Remove Checkout Location --
function prisonModules.removeCheckoutLocation()
    if GetResourceState('xt-prisonjobs') == 'started' then return end
    if CheckOutZone then pr_lib.target.removeZone(CheckOutZone) end
    CheckOutZone = nil
end

-- Create Prison Zone for Prison Break Distance Checks --
function prisonModules.createPrisonZone()
    if PrisonZone then return end
    local zone = { active = true, wasInside = false }
    function zone:remove() self.active = false end
    PrisonZone = zone

    CreateThread(function()
        while zone.active do
            local coords = GetEntityCoords(PlayerPedId())
            local inside = isInsidePrison(coords)
            if not inside and inJail then
                local escaped = pr_lib.callback.await('xt-prison:server:confirmBreakout', false)
                if escaped then
                    inJail = false
                    prisonModules.removeCheckoutLocation()
                    pr_lib.Notify({ title = locale('notify.escaped'), type = 'error' })
                    config.Dispatch(prisonBreakcfg.Center)
                end
            end
            zone.wasInside = inside
            Wait(750)
        end
    end)

    if GetResourceState('xt-prisonjobs') ~= 'started' then
        mainBlip = utils.createBlip('Prison', prisonBreakcfg.Center, 60, 0.7, 3)
    end
end

-- Removes All Prison Zones, Blips, etc --
function prisonModules.prisonCleanup()
    uniformRevision = uniformRevision + 1
    inJail = false
    TriggerServerEvent('xt-prison:server:saveJailTime')
    if PrisonZone then PrisonZone:remove() end
    PrisonZone = nil
    prisonModules.removeCheckoutLocation()
    prisonBreakModules.removeBlip()
    prisonBreakModules.removeHackZones()

    if DoesBlipExist(mainBlip) then
        RemoveBlip(mainBlip)
    end
end

-- Sets Player's Coords --
function prisonModules.setPlayerCoords(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z - 0.9, 0, 0, 0, false)
    SetEntityHeading(ped, coords.w)
    local dist = #(vec3(coords.x, coords.y, coords.z - 0.9) - GetEntityCoords(ped))
    return (dist <= 5)
end

-- Entering Prison --
local function enterPrison(setTime)
    local setServerJailTime = pr_lib.callback.await('xt-prison:server:setJailStatus', false, setTime)
    if not setServerJailTime then
        return false, 'jail_state_failed'
    end
    if XTPrison.refreshCache and not XTPrison.refreshCache() then return false,'cache_unavailable' end
    -- The login ped can still be Michael while appearance is being fetched.
    -- Never position or animate that temporary ped as the prisoner.
    if config.EnablePrisonOutfits then
        local deadline = GetGameTimer()+20000
        local male,female = GetHashKey('mp_m_freemode_01'),GetHashKey('mp_f_freemode_01')
        while not IsPedModel(PlayerPedId(),male) and not IsPedModel(PlayerPedId(),female) do
            if GetGameTimer() >= deadline then return false,'character_model_not_ready' end
            if playerState.prisonStatus ~= 'jailed' then return false,'sentence_changed' end
            Wait(100)
        end
    end
    local sentenceInfo = type(setServerJailTime) == 'table' and setServerJailTime or nil
    local sentenceMinutes = sentenceInfo and sentenceInfo.remainingMinutes or tonumber(setTime) or tonumber(playerState.jailTime) or 0

    if inJail and isInsidePrison(GetEntityCoords(PlayerPedId())) then
        prisonModules.setJailTime(sentenceMinutes)
        if config.EnablePrisonOutfits then prisonModules.applyPrisonUniform() end
        return true
    end
    inJail = false

    if type(config.Spawns) ~= 'table' or #config.Spawns == 0 then return false, 'spawn_missing' end

    if config.RemoveJob then
        local removed, reason = pr_lib.callback.await('xt-prison:server:removeJob', false)
        if not removed then
            return false, reason or 'job_removal_failed'
        end
    end

    local setJailTime = prisonModules.setJailTime(sentenceMinutes)
    if setJailTime then
        local isLifer = pr_lib.callback.await('xt-prison:server:liferCheck', false)

        DoScreenFadeOut(2000)
        while not IsScreenFadedOut() do Wait(25) end

        local RandomSpawn = config.Spawns[math.random(1, #config.Spawns)]
        if not RandomSpawn or not RandomSpawn.coords then return false, 'spawn_missing' end
        RequestCollisionAtCoord(RandomSpawn.coords.x, RandomSpawn.coords.y, RandomSpawn.coords.z)
        local deadline = GetGameTimer() + 10000
        local positioned = false
        repeat
            if prisonModules.setPlayerCoords(RandomSpawn.coords) then
                local ped = PlayerPedId()
                FreezeEntityPosition(ped, true)
                while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
                    Wait(0)
                end

                if HasCollisionLoadedAroundEntity(ped) then
                    if config.EnablePrisonOutfits and not prisonModules.applyPrisonUniform() then return false,'uniform_not_ready' end
                    inJail = true
                    positioned = true
                end
            end
            Wait(50)
        until positioned or GetGameTimer() >= deadline

        FreezeEntityPosition(PlayerPedId(), false)
        if not positioned then return false, 'spawn_timeout' end

        config.playJailSound()

        config.Emote(RandomSpawn.emote)
        prisonModules.createCheckoutLocation()

        DoScreenFadeIn(2000)
        while not IsScreenFadedIn() do Wait(25) end

        if config.EnterPrisonAlert.enable and not isLifer then
            CreateThread(function()
                local alertInfo = config.EnterPrisonAlert
                pr_lib.AlertDialog({
                    header = alertInfo.header,
                    content = sentenceInfo
                        and ('Sua pena foi definida em **%s %s**, usando **%s**.  \n%s'):format(sentenceInfo.amount, sentenceInfo.unit, sentenceInfo.clock == 'game' and 'tempo do jogo' or 'vida real', alertInfo.content)
                        or (locale('input.prison_sentence')):format(sentenceMinutes, alertInfo.content),
                    centered = true,
                    labels = { confirm = 'Close' }
                })
            end)
        elseif config.EnterPrisonAlert.enable and isLifer then
            pr_lib.Notify({ title = locale('notify.lifer'), type = 'error' })
        end

        if not isLifer then
            prisonModules.timeReductionLoop()
        end

        if GetResourceState('xt-prisonjobs') == 'started' then
            exports['xt-prisonjobs']:InitPrisonJob()
        end

        TriggerServerEvent('xt-prison:server:removeItems')
        return true
    end

    return false
end

function prisonModules.enterPrison(setTime)
    local deadline = GetGameTimer()+45000
    while enteringPrison and GetGameTimer()<deadline do Wait(50) end
    if enteringPrison then return false,'entry_busy' end
    enteringPrison = true
    local ok,result,reason = pcall(enterPrison,setTime)
    enteringPrison = false
    if not ok then return false,tostring(result) end
    if result == true then prisonModules.reconcilePrisonUniform() end
    return result,reason
end

-- Exiting Prison --
function prisonModules.exitPrison(isUnjailed)
    -- Confirm the server-owned value before returning confiscated items.
    if not XTPrison.refreshCache() then return false end
    if playerState.jailTime > 0 then return false end
    if playerState.jailTime > 0 and not isUnjailed then
        pr_lib.Notify({ title = (locale('notify.time_left')):format(playerState.jailTime), type = 'error' })
        return false
	elseif playerState.jailTime <= 0 or isUnjailed then
        local setJailTime = prisonModules.setJailTime(0)
        if setJailTime then
            inJail = false

            DoScreenFadeOut(2000)
            while not IsScreenFadedOut() do Wait(25) end

            if config.EnablePrisonOutfits then
                config.ResetClothing()
            end

            prisonModules.setPlayerCoords(config.Freedom)
            prisonModules.removeCheckoutLocation()

            Wait(500)
            DoScreenFadeIn(2000)
            while not IsScreenFadedIn() do Wait(25) end

            TriggerServerEvent('xt-prison:server:returnItems')

            if GetResourceState('xt-prisonjobs') == 'started' then
                exports['xt-prisonjobs']:CleanupPrisonJob()
            end

            return true
        end
	end

    return false
end

-- Reduce Jail Time Loop --
function prisonModules.timeReductionLoop()
    CreateThread(function()
        while inJail do
            if playerState.jailTime > 0 then
                local sentence = playerState.jailSentence
                local waitSeconds = sentence and tonumber(sentence.tickSeconds) or 60
                Wait(math.max(1, waitSeconds) * 1000)
                local newTime = pr_lib.callback.await('xt-prison:server:tickJailTime', false)
                if tonumber(newTime) then prisonModules.setJailTime(tonumber(newTime)) end
            elseif playerState.jailTime <= 0 then
                pr_lib.Notify({
                    title = locale('notify.checkout'),
                    icon = 'fas fa-unlock',
                    type = 'success'
                })
                break
            end
            if playerState.jailTime <= 0 then break end
        end
    end)
end

function prisonModules.applyPrisonUniform()
    if not config.EnablePrisonOutfits or playerState.prisonStatus ~= 'jailed' or (tonumber(playerState.jailTime) or 0) <= 0 then return false end
    local ped = PlayerPedId()
    local male,female=IsPedModel(ped,GetHashKey('mp_m_freemode_01')),IsPedModel(ped,GetHashKey('mp_f_freemode_01'))
    if not male and not female then return false end
    local outifitInfo = male and config.PrisonOufits.male or config.PrisonOufits.female
    SetPedComponentVariation(ped, 1, outifitInfo.mask.item, outifitInfo.mask.texture, 0)
    SetPedComponentVariation(ped, 3, outifitInfo.arms.item, outifitInfo.arms.texture, 0)
    SetPedComponentVariation(ped, 4, outifitInfo.pants.item, outifitInfo.pants.texture, 0)
    SetPedComponentVariation(ped, 6, outifitInfo.shoes.item, outifitInfo.shoes.texture, 0)
    SetPedComponentVariation(ped, 7, outifitInfo.accessories.item, outifitInfo.accessories.texture, 0)
    SetPedComponentVariation(ped, 8, outifitInfo.shirt.item, outifitInfo.shirt.texture, 0)
    SetPedComponentVariation(ped, 11, outifitInfo.jacket.item, outifitInfo.jacket.texture, 0)
    return true
end

-- Saved appearance may arrive late or replace the ped. One low-frequency worker
-- exists only while jailed; it never saves over the civilian appearance.
function prisonModules.reconcilePrisonUniform()
    uniformRevision = uniformRevision + 1
    if not config.EnablePrisonOutfits or not inJail or playerState.prisonStatus ~= 'jailed' then return end
    local revision = uniformRevision
    CreateThread(function()
        local slots = {[1]='mask',[3]='arms',[4]='pants',[6]='shoes',[7]='accessories',[8]='shirt',[11]='jacket'}
        while revision == uniformRevision do
            if not inJail or playerState.prisonStatus ~= 'jailed' or (tonumber(playerState.jailTime) or 0) <= 0 or not config.EnablePrisonOutfits then return end
            local ped = PlayerPedId()
            local outfit = IsPedModel(ped,GetHashKey('mp_m_freemode_01')) and config.PrisonOufits.male or config.PrisonOufits.female
            for slot,name in pairs(slots) do
                local component = outfit[name]
                if GetPedDrawableVariation(ped,slot) ~= component.item or GetPedTextureVariation(ped,slot) ~= component.texture then
                    prisonModules.applyPrisonUniform()
                    break
                end
            end
            Wait(1000)
        end
    end)
end

return prisonModules

