---
status: awaiting_human_test
trigger: Missing prison locks, inaccessible hack settings, single NPC/alarm and no animated gizmo
---

## Symptoms

Doorlock has no forge-prison group; escape panel exposes only numeric rules.
User requests multiple hack sites, NPCs and alarms and drill preview with gizmo.
Alarm did not sound on one failure with configured chance 10%.

## Evidence

- Doors map was empty and absent from persisted settings; no in-game door capture.
- Per-terminal settings existed under Locations rather than Escape panel.
- Single NPC lifecycle and single native alarm only.
- Plain placePed was used instead of animated preview plus gizmo.

## Current Focus

next_action: validate captured locks, gizmo drill alignment, multiple NPCs and alarm test in FiveM.

## Verification

Eight isolated suites passed, including real menu routes and real preview/NPC/alarm
modules with native mocks. 40 XT Lua files and two PR Bridge door adapters passed
luac55. No server restart, live SQL or changes to ox_doorlock/PS Housing were made.
Actual map geometry must be captured in-game; native GTA alarm names remain global,
not independent spatial emitters. Functional approval remains pending.
