-- Isolated SQL contract test: no live database is accessed.
local hasStatus, migrated, updates = false, false, 0
local rows={old={jailtime=9},released={jailtime=0}}
CreateThread=function(fn) fn() end
GetGameTimer=function() return 0 end
XTPrison={log=function() end}
pr_lib={activeBridges={frameworks='qbx'},database={ready=function(fn) fn() end,query=function(sql)
    if sql:find('INFORMATION_SCHEMA.TABLES',1,true) then return {{count=1}} end
    if sql:find('INFORMATION_SCHEMA.COLUMNS',1,true) then
        if sql:find("COLUMN_NAME = 'status'",1,true) then return {{count=hasStatus and 1 or 0}} end
        if sql:find("COLUMN_NAME = 'sentence'",1,true) then return {{count=1}} end
        return {{count=0}}
    end
    if sql:find('ALTER TABLE xt_prison ADD COLUMN status',1,true) then hasStatus=true;migrated=true end
    if sql:find('UPDATE xt_prison SET status',1,true) then
        updates=updates+1
        for _,row in pairs(rows) do row.status=row.jailtime>0 and 'jailed' or 'free' end
    end
    return {}
end}}
local db=dofile('modules/server/db.lua')
assert(db.awaitReady() and migrated and updates==1)
assert(rows.old.status=='jailed' and rows.old.jailtime==9 and rows.released.status=='free')
rows.old.status='fugitive'
db=dofile('modules/server/db.lua')
assert(db.awaitReady() and updates==1 and rows.old.status=='fugitive','Restart must not reset fugitive status')
print('PASS: automatic status migration, preserved sentences, existing fugitive status unchanged on restart')
