# Project State

_Last updated: 2026-11-25_

## Current phase
**Phase 5: Subscriptions, savings, custom reminders** is built and committed. Phases 4 and 5 and the redesign were verified on the TECNO KJ7 (release build, wireless debugging): Home, Dues (create, partial payment, timeline), subscriptions (add, pay), Activity, light/dark switch (completes in under half a second). The v1 to v2 migration ran on real data without loss.

## Done
- Phases 1-4 (setup, ledger, money screens, dashboard, dues and people).
- **Schema v2**: `subscriptions.anchor_day` (keeps a 31st billing day after short months), with a tested v1 -> v2 migration and a schema snapshot.
- **Subscriptions**: list with monthly cost and paid-this-month, renewal countdowns, "Pay" sheet (amount editable) that creates a linked expense and moves the next date forward, pause/resume/cancel/delete, per-subscription history and spent this month/year/all time, form with idea chips (Spotify, Google One, iCloud, VPS, Warehouse).
- **Savings**: total saved, goal progress per savings account, Add to savings / Withdraw (pre-filled transfers), create savings account shortcut.
- **Custom reminders**: add/edit/delete, repeat (none/daily/weekly/monthly/every N days), active switch, "Pay" opens Add expense pre-filled; repeating reminders roll forward on app start/resume.
- 80 tests, `flutter analyze` clean.

## Phase 6 (notifications): built, partly verified
- Verified on the TECNO KJ7: permission prompt, instant test notification, scheduled alarms registered with AlarmManager, scheduled test delivered while the app was open.
- NOT verified / failing: delivery while the app is in the background on this phone (HiOS restricts background apps). Needs the phone's background/autostart setting turned on, then a retest. Reboot survival not yet tested.

## Phase 7 (app lock): built and verified
- On the TECNO KJ7: PIN setup and confirm, FLAG_SECURE active (screenshots go blank), PIN check from the settings sheet, turning the lock off. Lock screen behaviour (wrong PIN, lockout, re-lock on resume, timeouts) is covered by widget tests; fingerprint prompt not exercised.

## Phase 8 (backup and restore): built, tests pass, not yet phone-tested
- Backup zip = `hisaab.sqlite` (VACUUM INTO) + `manifest.json`. Local export (share sheet) and import (file picker) need no setup. Restore checks the file first (newer schema, damaged, not a backup), keeps a rollback copy, swaps the DB and reschedules reminders.
- Backup & restore screen at `/backup` (More > Backup & restore; the "backup" reminder opens it). Cloud: Google Drive appdata folder (needs `--dart-define=GOOGLE_SERVER_CLIENT_ID`) and iCloud via Swift plugin; latest 10 kept. Setup steps are in README.
- 125 tests, `flutter analyze` clean.
- Phone-verified (TECNO KJ7, release): Backup screen renders, Export makes `hisaab_backup_<date>.zip` (7 KB) and opens the share sheet, "Last backup" updates.
- Not verified: import/restore on the phone, Google Drive (needs Cloud setup), iCloud (needs a Mac).

## Next
1. Phase 9: polish and tests (empty states, app icon, source month history, forms/More/Settings redesign).
2. Phone test of backup export/import.

## Open items
- Month-by-month history on Source details still not built.
- Scheduled notifications do not arrive in the background on the TECNO/HiOS phone until background activity/autostart is allowed. Reboot survival untested.
- iOS parts (iCloud, Face ID, notifications) tested later on a Mac.