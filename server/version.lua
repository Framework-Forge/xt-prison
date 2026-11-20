local REPO_OWNER = "Framework-Forge"
local REPO_NAME = "xt-prison"
local VERSION_CHECK = true

if IsDuplicityVersion() then
    CreateThread(function()
        Wait(5000)
        if VERSION_CHECK then
            if pr_lib and pr_lib.versionCheck then
                pr_lib.versionCheck(("%s/%s"):format(REPO_OWNER, REPO_NAME))
            end
        end
    end)
end
