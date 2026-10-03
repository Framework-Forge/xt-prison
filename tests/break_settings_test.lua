local path='E:/[FIVEM]/Forge-Core/resources/[standalone]/xt-prison/'
vec4=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end
XTPrison={load=function() return {EnterPrisonAlert={enable=true,header='Welcome',content='Message'}} end}
local api=dofile(path..'modules/break_settings.lua')
local settings={general={},locations={hacks={{coords={x=0,y=0,z=0},radius=1,gate='gate'}}},prisonBreak={}}
api.normalize(settings)
local zone=settings.locations.hacks[1]
assert(zone.game=='CircuitBreaker' and zone.item=='trojan_usb' and zone.itemCount==1)
assert(settings.entryAlert.enable and settings.prisonBreak.alarm.name=='PRISON_ALARMS')
zone.shape='poly'; zone.thickness=4
zone.points={{x=-2,y=-2,z=0},{x=2,y=-2,z=0},{x=2,y=2,z=0},{x=-2,y=2,z=0}}
zone.animation={x=1,y=1,z=0,w=90}; zone.game='PlasmaDrilling'
api.normalize(settings)
assert(api.contains(zone,{x=0,y=0,z=0}))
assert(not api.contains(zone,{x=4,y=0,z=0}))
assert(not api.contains(zone,{x=0,y=0,z=10}))
local client, prison={}, {HackZones={{}}}
api.apply(settings,client,prison)
assert(prison.HackZones[1].game=='PlasmaDrilling' and prison.HackZones[1].animation.w==90)
assert(client.EnterPrisonAlert==settings.entryAlert)
settings.npcs.doctor={{model='doctor',coords={x=1,y=2,z=3,w=4},duration=5},{model='doctor2',coords={x=5,y=6,z=7,w=8},duration=3}}
settings.prisonBreak.alarms[2]={coords={x=10,y=20,z=30},name='PRISON_ALARMS',interior='int_prison_main',prop='prison_alarm'}
api.normalize(settings);api.apply(settings,client,prison)
assert(#client.PrisonDoctors==2 and client.PrisonDoctors[2].coords.w==8)
assert(#prison.Alarms==2)
zone.animation.x=20
assert(not pcall(api.normalize,settings))
zone.animation=nil;zone.points={}
assert(not pcall(api.normalize,settings))
print('PASS: legacy defaults, polygon containment, drill position and runtime propagation')
