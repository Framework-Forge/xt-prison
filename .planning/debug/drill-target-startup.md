---
status: awaiting_human_test
trigger: targets missing after restart and Fleeca/Plasma fail before animation
---

## Evidence

Glitch signatures checked in installed source: StartDrilling(), StartPlasmaDrilling(number).
XT chooses the generic cached minigame adapter; this can select an unrelated fallback.
Client targets initialize from legacy defaults before settings arrive; a partial zone
creation leaves next(HackZones) preventing subsequent creation. Settings fetch uses
default callback timeout and no retry; client startup hook uses onResourceStart rather
than explicit onClientResourceStart. Checkout refresh precedes hack refresh in one handler.
Minigame exceptions are currently reported as failed attempts and consume items/alarm.

## Current Focus

next_action: restart updated PR Bridge and XT Prison; reproduce the previously working
DataCrack first and collect the actual notification reason and unconditional F8 trace.
Latest human test reports initialization exception for all five games, with no logs.
Underlying runtime minigame failure is not yet confirmed or resolved.

## Changes and verification

Explicit bridge Glitch loading no longer relies on cached adapter selection; signatures
match installed exports. Preload DRILLING/Fleeca and VAULT_LASER/Plasma, model/animation.
Ped starts idle at saved position; session cleanup retained. Initialization exceptions
are not normal hack failures and do not send item removal/alarm chance events.
Client startup hook corrected; persisted settings gate target creation. Separate target
refresh handler, atomic partial rollback, bounded retry and normalized player lifecycle.
Real config/adapter/client paths exercised by drill_target_startup_test.lua.
Lua syntax and full regression suite passed. No resource restart or persisted data edit.

## Follow-up: silent error affecting every game (2026-10-02)

Confirmed from source: XTPrison.log delegated errors to PRDebug.error, whose emit
returns without printing when Config.Debug is false. This explains the missing logs,
not necessarily the minigame exception itself. XT error logs now bypass this debug
filter; other log levels retain bridge behavior. Hack catches retain traceback and
identify terminal, game and execution stage, and the notification shows the actual
first-line cause. Explicit manifest publication added for the Glitch client adapter,
matching the earlier emotes/doorlock file publication approach. Missing download is
a hypothesis, not a confirmed runtime cause. No changes to Glitch internals, saved
animation positions or user settings. Lua syntax and 13 test suites passed, including
actual error logger behavior with debug disabled and all five adapter dispatch paths.
FiveM verification remains required; mock exports cannot establish runtime success.

## Follow-up: DataCrack approved, Fleeca still throws (2026-10-02)

Human test confirms DataCrack works after adapter publication; Fleeca notification
still reports an exception at configs/prisonbreak.lua:45. Screenshot truncates the
actual underlying error; requested full F8 trace. Removed bridge-owned initialization
from Fleeca dispatch: it now calls StartDrilling() directly with zero arguments as
documented and as implemented by the installed Glitch export. Glitch already owns
model/animation/scaleform initialization and awaits a boolean result. XT saved ped
position, animation and session cleanup remain unchanged. Plasma path unchanged.
Regression checks enforce zero arguments, no bridge Fleeca scaleform setup, true/
false result handling and original exception preservation. Runtime fix awaits test;
do not infer the missing exception cause from the cropped notification.

Full human F8 trace subsequently confirms the cause: Fleeca line 267 calls absent
glitch-notifications:ShowNotification before playDrillingSequence. Installed shared
config enabled usingGlitchNotifications=true. Set this optional provider flag to
false in Glitch shared/config.lua; this also prevents the identical missing-export
dependency in Plasma. XT success/failure notifications remain through PR Bridge.
No Glitch minigame implementation changes. Regression test extracts the installed
Fleeca Start body, reproduces the exact missing-export exception with flag enabled,
and confirms animation/result callback are reached with the flag disabled. Restart
Glitch as well as PR Bridge/XT to clear the prior exception's active drill state.
