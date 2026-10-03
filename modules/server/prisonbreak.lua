local globalState       = XTPrison.world
local db                = XTPrison.load 'modules.server.db'
local prisonBreakcfg    = XTPrison.load 'configs.prisonbreak'
local utils             = XTPrison.load 'modules.server.utils'

local prisonModules = {}
local alarmTokens={}
local function gates(zone) return zone.gates or {zone.gate} end
local function gateOpenElsewhere(gate,except)
    for id,zone in ipairs(prisonBreakcfg.HackZones) do
        local terminal=globalState[('PrisonTerminal_%s'):format(id)]
        if id~=except and terminal and terminal.isHacked then
            for _,name in ipairs(gates(zone)) do if name==gate then return true end end
        end
    end
    return false
end
function prisonModules.setEscapeAlarm(id,state)
    if type(state)~='boolean' then return false end
    local found
    for _,escape in ipairs(prisonBreakcfg.Escapes or {}) do if escape.id==id then found=escape;break end end
    if not found then return false end
    local current=globalState.escapeAlarms or {};local alarms={}
    for key,value in pairs(current) do alarms[key]=value end
    alarms[id]=state;globalState.escapeAlarms=alarms
    alarmTokens[id]=(alarmTokens[id] or 0)+1
    if state then
        local token,generation=alarmTokens[id],pr_lib.cache.get('xt-prison:configurationRevision')
        SetTimeout((found.alarmLength or prisonBreakcfg.AlarmLength)*60000,function()
            if alarmTokens[id]==token and generation==pr_lib.cache.get('xt-prison:configurationRevision') then prisonModules.setEscapeAlarm(id,false) end
        end)
    end
    return true
end

function prisonModules.ownsAttempt(src,id)
    if not utils.terminalDistanceCheck(src,id) then return false end
    local terminal=globalState[('PrisonTerminal_%s'):format(id)]
    return terminal and terminal.isBusy and terminal.lastHacker==src and not terminal.isHacked or false
end

-- Breakout of Prison --
function prisonModules.prisonBreakout(src)
    local player = getPlayer(src)
    local playerState = XTPrison.playerState(src)
    if not playerState then return end

    setJailTime(src, 0) -- Set jail time to zero

    -- Delete Confiscated Inv --
    local CID = getCharID(src)
    local confiscatedItems = pr_lib.database.scalar(db.GET_ITEMS, { CID })
    confiscatedItems = json.decode(confiscatedItems or '[]')
    if confiscatedItems and next(confiscatedItems) then
        pr_lib.database.execute(db.CLEAR_CONFISCATED_ITEMS, { CID })
    end

    return (playerState.jailTime == 0)
end

-- Countdown for Alarms to Turn Off --
function prisonModules.alarmCountdown()
    local generation=pr_lib.cache.get('xt-prison:configurationRevision')
    return SetTimeout((prisonBreakcfg.AlarmLength * 60000), function()
        if generation~=pr_lib.cache.get('xt-prison:configurationRevision') then return end
        globalState.prisonAlarms = false
    end)
end

-- Set Terminal Hacked State --
function prisonModules.setTerminalHackedState(src, terminalID, setState)
    if type(setState) ~= 'boolean' then return false end
    local dist = utils.terminalDistanceCheck(src, terminalID)
    if not dist then return false,'Jogador fora da zona do terminal.' end

    if not globalState[('PrisonTerminal_%s'):format(terminalID)] then return false,'Terminal não encontrado no cache.' end

    if globalState[('PrisonTerminal_%s'):format(terminalID)].isHacked == setState then return setState end

    if not globalState[('PrisonTerminal_%s'):format(terminalID)].isBusy then
        return false,'Não há tentativa ativa neste terminal.'
    end
    if globalState[('PrisonTerminal_%s'):format(terminalID)].lastHacker ~= src then
        local cid = getCharID(src)
        utils.banPlayer(src, cid)
        return false,'Tentativa não pertence a este jogador.'
    end

    local zone=prisonBreakcfg.HackZones[terminalID]
    if setState then
        if #gates(zone)==0 then return false,'Terminal sem portas selecionadas.' end
        if (zone.game=='FleecaDrilling' or zone.game=='PlasmaDrilling') and not zone.animation then return false end
        local changed={}
        for _,gate in ipairs(gates(zone)) do
            local opened,reason=XTPrison.setGateState(gate,false)
            if not opened then
                for _,name in ipairs(changed) do if not gateOpenElsewhere(name,terminalID) then XTPrison.setGateState(name,true) end end
                return false,('Porta %s: %s'):format(gate,reason or 'estado não aplicado')
            end
            changed[#changed+1]=gate
        end
    end
    globalState[('PrisonTerminal_%s'):format(terminalID)] = {
        isHacked = setState,
        isBusy = false,
        gate = prisonBreakcfg.HackZones[terminalID].gate,
        gates = gates(zone),
        escapeId = zone.escapeId,
    }

    if setState then
        prisonModules.setTerminalCooldown(terminalID)
    end

    return (globalState[('PrisonTerminal_%s'):format(terminalID)].isHacked == setState)
end

-- Set Terminal Busy State --
function prisonModules.setTerminalBusyState(src, terminalID, setState)
    if type(setState) ~= 'boolean' then return false end
    if type(terminalID)~='number' or terminalID%1~=0 or not prisonBreakcfg.HackZones[terminalID] then return false,'Terminal inválido.' end
    local terminal = globalState[('PrisonTerminal_%s'):format(terminalID)]
    if not terminal then return false,'Terminal ainda não sincronizado no servidor.' end
    -- Cleanup is not a new attempt: it must work after success, movement,
    -- cancellation or disconnect, without clearing somebody else's reservation.
    if not setState then
        if not terminal.isBusy then return true end
        if terminal.lastHacker~=src then return false,'Tentativa não pertence a este jogador.' end
        globalState[('PrisonTerminal_%s'):format(terminalID)] = {
            isHacked=terminal.isHacked, isBusy=false,
            gate=prisonBreakcfg.HackZones[terminalID].gate,
            gates=gates(prisonBreakcfg.HackZones[terminalID]),
            escapeId=prisonBreakcfg.HackZones[terminalID].escapeId,
        }
        return true
    end
    local dist = utils.terminalDistanceCheck(src, terminalID)
    if not dist then return false,'Jogador fora da zona do terminal.' end

    if terminal.isHacked then return false,'Terminal em cooldown.' end
    if terminal.isBusy then return false,terminal.lastHacker==src and 'Tentativa já está em andamento.' or 'Outro jogador está usando o terminal.' end
    if setState then
        if (globalState.copCount or 0)<prisonBreakcfg.MinimumPolice then return false,'Policiais insuficientes.' end
        local zone=prisonBreakcfg.HackZones[terminalID]
        if #gates(zone)==0 then return false,'Selecione as portas deste terminal.' end
        if (zone.game=='FleecaDrilling' or zone.game=='PlasmaDrilling') and not zone.animation then return false,'Configure a posição animada do ped com o gizmo.' end
        if zone.item and zone.item~='' and (pr_lib.inventory.GetItemCount(src,zone.item) or 0)<(zone.itemCount or 1) then return false,'Item insuficiente: '..zone.item end
    end

    local isHacked = globalState[('PrisonTerminal_%s'):format(terminalID)].isHacked
    globalState[('PrisonTerminal_%s'):format(terminalID)] = {
        isHacked = isHacked,
        isBusy = setState,
        lastHacker = src,
        gate = prisonBreakcfg.HackZones[terminalID].gate,
        gates = gates(prisonBreakcfg.HackZones[terminalID]),
        escapeId = prisonBreakcfg.HackZones[terminalID].escapeId,
    }

    return (globalState[('PrisonTerminal_%s'):format(terminalID)].isBusy == setState)
end

function prisonModules.releasePlayerTerminals(src)
    if not src then return end
    for id in ipairs(prisonBreakcfg.HackZones) do
        local terminal=globalState[('PrisonTerminal_%s'):format(id)]
        if terminal and terminal.isBusy and terminal.lastHacker==src then
            prisonModules.setTerminalBusyState(src,id,false)
        end
    end
end

-- Set Terminal Cooldown --
function prisonModules.setTerminalCooldown(terminalID)
    local generation = pr_lib.cache.get('xt-prison:configurationRevision')
    SetTimeout((prisonBreakcfg.TerminalCooldowns * 60000), function()
        if generation ~= pr_lib.cache.get('xt-prison:configurationRevision') or not prisonBreakcfg.HackZones[terminalID] then return end
        globalState[('PrisonTerminal_%s'):format(terminalID)] = {
            isHacked = false,
            isBusy = false,
            lastHacker = nil,
            gate = prisonBreakcfg.HackZones[terminalID].gate,
            gates = gates(prisonBreakcfg.HackZones[terminalID]),
            escapeId = prisonBreakcfg.HackZones[terminalID].escapeId,
        }
        for _,gate in ipairs(gates(prisonBreakcfg.HackZones[terminalID])) do
            if not gateOpenElsewhere(gate,terminalID) then XTPrison.setGateState(gate,true) end
        end
    end)
end

return prisonModules

