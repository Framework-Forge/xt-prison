---
status: awaiting_human_test
trigger: Missing PR Bridge client doorlock file and request for independent escape environments
---

## Evidence

- Client adapter exists locally, but runtime reported LoadResourceFile missing.
- PR Bridge manifest previously used glob files only; explicit adapter entries added.
- Old flat terminals shared global alarm cache and single gate per terminal.
- Housing creation contract inspected in ps-housing/server/doors.lua; prison adapter
  uses same persisted geometry/group/ID/native handoff contract without housing edits.

## Changes

Legacy migration to Fuga original; escapes own doors, terminals and alarm points.
Multi-select gates; five Glitch games; existing animated ped/gizmo used for drills.
Scoped cache alarms/timers, 100 percent failure alarm default per escape, multi-gate
rollback, shared-gate cooldown protection, and server-confirmed success notification.
Missing client module no longer aborts the entire editor; explicit restart diagnostic.

## Verification

luac syntax and isolated regression suites including real menu routes, native mocks,
cache revisions, adapter creation and escape isolation. No live database mutation
or FXServer restart performed. Server client mount not reproduced locally.

## Current Focus

next_action: restart base with current pr_bridge manifest, capture actual door geometry,
test Fuga A/B isolation, verify persisted group and Fleeca/Plasma ped alignment in FiveM.
Native GTA alarm names are global; points with same name are not independent spatial emitters.
