---
status: awaiting_human_test
trigger: XT Prison does not create locks in the modified ox_doorlock
---

## Symptoms

Expected: prison gates registered using the housing contract. Actual: absent locks.
Errors: not provided. Reproduction: initialize prison/hack gates.

## Evidence

- XT only looked up names; no createDoor call or door geometry existed.
- Housing supplies model, coordinates, heading/rotation, group and initial distance.
- Modified doorlock creates groups from doorGroup; no separate group export exists.
- getDoorFromName returns a reduced object, not animation/type information.

## Current Focus

hypothesis: registration is missing, not merely an incompatible lock event.
next_action: test existing gates in FiveM; obtain geometry for any missing lock.

## Verification

35 XT Lua files and the PR Bridge adapter passed luac55 validation.
door_provider_test.lua passed creation, parameter preservation, duplicate guard,
provider unavailable and locking/unlocking cases. No server restart or live SQL
was performed. Missing geometry remains an explicit setup requirement.
