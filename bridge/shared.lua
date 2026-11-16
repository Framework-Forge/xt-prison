XTPrison = XTPrison or {}
local moduleCache = {}

local translator = pr_lib.locale(GetCurrentResourceName())

function XTPrison.load(path)
    if moduleCache[path] ~= nil then return moduleCache[path] end

    local module = pr_lib.load(path)
    moduleCache[path] = module == nil and true or module
    return moduleCache[path]
end

function locale(key, ...)
    return translator(key, ...)
end

if IsDuplicityVersion() then
    function XTPrison.notifyPlayer(target, data)
        TriggerClientEvent('xt-prison:client:notify', target, data)
        return true
    end
end

function XTPrison.log(level, message)
    -- Runtime failures must remain visible even when PR Bridge debug is disabled.
    if level == 'error' then
        print(('[xt-prison][error] %s'):format(tostring(message)))
        return
    end
    local logger = pr_lib.print and pr_lib.print[level]
    if type(logger) == 'function' then
        logger(message)
        return
    end

    print(('[xt-prison][%s] %s'):format(level, message))
end

