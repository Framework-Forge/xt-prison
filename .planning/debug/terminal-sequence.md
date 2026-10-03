---
status: awaiting_human_test
trigger: successful Fleeca followed by DataCrack reports failed unlock; same target inactive
---

## Symptoms

Human confirms locks and Fleeca work. Sequential hacks of different escapes can
report minigame success then refuse final unlock; a different target later works.
Expected: per-terminal attempts cleanly finalize without contaminating another.

## Current Focus

hypothesis: successful completion carries isBusy but drops lastHacker, while release
rejects all hacked terminals; client unfreezes before final server distance check.
next_action: restart XT Prison and verify Fleeca escape A -> DataCrack escape B,
then wait each configured cooldown and retry the same targets in FiveM.

## Evidence

setTerminalHackedState copies isBusy into completed record without lastHacker.
setTerminalBusyState checks distance/cooldown even when releasing. ownsAttempt does
not require isBusy. Client unfreezes after minigame before the post-hack progress.
Configured cooldown deliberately disables the same successfully hacked target.
No evidence yet that game outcome variables leak between Fleeca and DataCrack.

## Fix and verification

terminal_sequence_test.lua failed against original server code because completed
terminal kept isBusy=true. Completion now clears busy/owner atomically. Owned
release works outside distance and after completion; duplicate starts are rejected,
released attempts no longer authorize item/alarm events, and logout/disconnect
release only the affected player's reservations. Late completion of an idle terminal
returns a refusal instead of incorrectly banning. Cooldown retains gate metadata.
Client holds position again after Glitch exits until progress and final confirmation,
then session cleanup unfreezes on success/refusal/error. Existing door provider and
minigame implementations unchanged. Target inactivity during cooldown remains by
design; missing required items can also hide the option.

Lua syntax validation and all 15 test suites passed. New actual client/server module
integration checks cover sequential independent escapes, another target sharing an
open door, separate/shared cooldowns, rejected completion -> retry -> other target,
duplicate start, ownership, disconnect and final-confirmation position hold. Native
and provider doubles do not substitute for FiveM confirmation; no server restart
or saved settings/database edits performed.
