---
status: awaiting_human_test
trigger: police grade 1 door access, registered doors fail after hack, hand prop remains
---

## Symptoms

Manual access must require police grade 1; successful Data Crack reports unlock failure
despite two selected registered doors. Tablet remains after completing the hack.

## Evidence

Doorlock setDoorState checks global source even on exported invocation. Source 0/player
context can deny a scripted unlock. Existing adapter does not verify state or explain refusal.
XT clears ped tasks but never cancels Scully emote/prop cache. Drill minigames normally
delete their own props, but an exceptional return requires scoped fallback cleanup.

## Current Focus

next_action: restart with current PR Bridge files mounted, verify police grade 0/1
manual access, complete Data Crack opening both selected doors, and verify no tablet/drill
after success/failure. Repeat on existing doors without recreating their geometry.

## Verification

Actual installed doorlock state function reproduced player/zero source refusal;
local server context + adapter readback succeeds without changing network ACL.
Existing/new doors receive police=1 and no character/item/passcode/lockpick alternatives.
Real client hack flow cleans emote session and releases terminal on successful unlock,
refusal, minigame exception and progress exception. Scoped props test preserves unrelated
objects. Lua syntax checked with user-provided luac. No live restart/database mutation.
