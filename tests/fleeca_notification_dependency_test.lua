local root='E:/[FIVEM]/Forge-Core/resources/[standalone]/glitch-minigames/'
dofile(root..'shared/config.lua')
assert(config.usingGlitchNotifications==false,'Forge must not depend on glitch-notifications')
local file=assert(io.open(root..'client/fleecaDrilling/fleecaDrilling.lua','r'))
local source=file:read('*a');file:close()
local body=assert(source:match('(Drilling%.Start = function%(callback%).-)%s*Drilling%.Draw = function'))
local notifications,animations=0,0
local env={config=config,Drilling={Init=function() return true end},
    exports=setmetatable({}, {__index=function()
        notifications=notifications+1
        error('No such export ShowNotification in resource glitch-notifications')
    end}),loadDrillSound=function() end,
    playDrillingSequence=function(callback) animations=animations+1;callback() end}
env.Drilling.Update=function(callback) env.Drilling.Active=false;callback(true) end
assert(load(body,'@installed-Fleeca-Start','t',env))()
-- Reproduce the exact reported exception from the installed Start implementation.
config.usingGlitchNotifications=true
local ok,err=pcall(env.Drilling.Start,function() end)
assert(not ok and tostring(err):find('No such export ShowNotification',1,true))
assert(animations==0,'Missing notification export aborts before the animation')
env.Drilling.Active=false
config.usingGlitchNotifications=false
local result
env.Drilling.Start(function(success) result=success end)
assert(result==true and animations==1 and notifications==1,'Disabled optional dependency lets Fleeca reach animation and result without external notifications')
print('PASS: installed Fleeca Start reproduces missing ShowNotification; Forge config bypasses dependency and reaches animation/result')
