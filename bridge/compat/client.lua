local prisonModules = XTPrison.load 'modules.client.prison'

-- QB/QBX Prison Compat Events --
RegisterNetEvent('prison:client:Enter', function(setTime)
    XTPrison.log('warn', ('%s triggered deprecated event prison:client:Enter, use callback'):format(GetInvokingResource() or 'unknown'))
    prisonModules.enterPrison(setTime)
end)

RegisterNetEvent('prison:client:Leave', function()
    XTPrison.log('warn', ('%s triggered deprecated event prison:client:Leave, use callback'):format(GetInvokingResource() or 'unknown'))
    prisonModules.exitPrison(false)
end)

RegisterNetEvent('prison:client:UnjailPerson', function()
    XTPrison.log('warn', ('%s triggered deprecated event prison:client:UnjailPerson, use callback'):format(GetInvokingResource() or 'unknown'))
    prisonModules.exitPrison(true)
end)

