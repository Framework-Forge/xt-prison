---
status: awaiting_human_test
trigger: "Confirmar prisao nao teleporta nem notifica; integrar a gestao e F9 do Forge Core."
---

## Symptoms

Expected: selected player enters prison after confirming sentence; errors are visible.
Actual: no teleport or notification after filling dialog.
Reproduction: /jail, select own character, fill sentence and confirm.

## Current Focus

hypothesis: default 10-second bridge client callback expires while the user fills the form; prison entry can also exceed that duration.
next_action: restart xt-prison and forge-core; test a form taking over 10 seconds, prison entry/release, administrative actions and F9 visibility.

## Evidence

- secure_server.lua awaitOx uses defaultTimeout of 10000; sv_commands ignores non-table reply, including nil/timeout.
- enterPrison waits fade-out, collision loading up to 10000 and fade-in; default entry timeout is also 10000.
- Failed entry can leave jailTime > 0, causing a retry to update the sentence without retrying teleport.
- Existing Forge menus have no XT Prison data or actions.

## Resolution

Root cause reproduced using the actual secure bridge callback: a 25-second form times out at 10 seconds with the old call; explicit 120-second deadline accepts it. Actual client entry reproduced at over 12 seconds with fades/collision.

Fix: explicit form/entry waits, common server actions with persistence/rollback, read-only self sentence acknowledgement, visible error reasons and retry of failed entry. Forge Core adds bridge-backed administrative actions and conditional F9/management information. Provider access is isolated in a PR Bridge adapter, with no new hard dependency on XT Prison.

Isolated verification: cache/database, administrative commands, real bridge timeout/action/provider integration and actual client/menu tests passed. Live FXServer/SQL operations were not performed; FiveM approval pending. Skill workflow executed inline; no agent spawning.
