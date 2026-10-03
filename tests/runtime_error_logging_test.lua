local bridge='E:/[FIVEM]/Forge-Core/resources/[forge]/[forge-scripts]/pr_bridge/'
local output,debugCalls={},0
local originalPrint=print
print=function(message) output[#output+1]=message end
GetCurrentResourceName=function() return 'xt-prison' end
IsDuplicityVersion=function() return false end
pr_lib={locale=function() return function(key) return key end end,
    print={error=function() debugCalls=debugCalls+1 end,info=function() debugCalls=debugCalls+1 end}}
XTPrison=nil
dofile('bridge/shared.lua')
XTPrison.log('error','minigame exception with debug disabled')
assert(#output==1 and output[1]:find('minigame exception',1,true))
assert(debugCalls==0,'Error logging must bypass the debug-only logger')
XTPrison.log('info','ordinary diagnostics')
assert(debugCalls==1,'Non-error logs retain existing bridge behavior')
local manifest=assert(io.open(bridge..'fxmanifest.lua','r'))
local contents=manifest:read('*a');manifest:close()
assert(contents:find('"bridge/minigames/glitch/client.lua"',1,true),'Explicit Glitch adapter download entry required')
print=originalPrint
print('PASS: XT runtime errors remain visible with debug disabled; Glitch adapter explicitly published')
