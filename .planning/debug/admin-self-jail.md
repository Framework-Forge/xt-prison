---
status: awaiting_human_test
trigger: "Administrador nao aparece na lista e deseja prender o proprio personagem para teste."
---

## Symptoms

Expected: administrator can select their loaded character in the jail dialog.
Actual: empty list when no other player is nearby.
Reproduction: open jail dialog alone; user supplied screenshot with no options.
Timeline: reported during XT Prison migration validation; earlier history unspecified.

## Current Focus

hypothesis: sv_commands.lua excludes playerSource == source and checks only police job, not bridge admin authorization.
next_action: restart xt-prison in FiveM and verify /jail self-selection, entry and /unjail own ID as admin.

## Evidence

- sv_commands.lua filters playerSource ~= source before constructing options.
- /jail, /unjail and roster actions check utils.isCop only.
- PR Bridge exposes ace.isAdminWhitelisted, ace.isPlayerAceAllowed and framework.HasPermission.

## Resolution

root_cause: command excludes its caller, and jail/unjail/roster authorization checks police job only.
fix: bridge-backed admin checks, self inclusion only for admins, shared management authorization, post-dialog reauthorization, loaded-player/proximity/bucket filters and no false success on failed entry.
verification: admin_self_jail_test.lua and cache_database_test.lua pass; all 30 resource Lua files pass luac55. In-game approval pending.
files_changed: modules/server/utils.lua, server/sv_commands.lua, server/sv_roster.lua, tests/admin_self_jail_test.lua, documentation.
Work performed inline under the skill's no-auto-spawn fallback. No server restart, database writes or changes to other runtime resources.
