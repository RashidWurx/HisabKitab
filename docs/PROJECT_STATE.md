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
- (Done in phase 9) Month-by-month history on Source details.
- Scheduled notifications do not arrive in the background on the TECNO/HiOS phone until background activity/autostart is allowed. Reboot survival untested.
- iOS parts (iCloud, Face ID, notifications) tested later on a Mac.
## Notifications, icon and app lock (after phase 8)
- Icon: adaptive + themed launcher icon from `icon.png`, white `ic_stat_hisaab` notification icon.
- Reminders use a loud channel (alarm stream, max importance, FLAG_INSISTENT so it keeps ringing until opened or cleared). Ringtone is chosen from the system picker; the channel id encodes the sound because Android channel sounds are immutable. Exact alarms are used when allowed. Notification ids are stable (FNV hash of the plan key).
- Missed reminders inbox (More, and the bell on Home): every scheduled reminder is logged in `notification_log` (schema v3). Past and unhandled rows are "missed". Open / In 1 hour (snooze) / Done / Clear all. Notification buttons per type: Received/Extend/Later (dues), Pay/Later (subscriptions), Done/Later (reminders).
- Phone-verified (TECNO, USB): v2 to v3 upgrade keeps data, scheduled test fires with the app swiped away, appears in Missed reminders, In 1 hour schedules an exact alarm.
- Not verified: custom ringtone picking, notification action buttons, reboot survival, HiOS autostart.
- App lock fix: fingerprint prompt no longer loops (lifecycle events within 2 s of a biometric prompt are ignored). Needs a phone check.

## Phase 9 (in progress)
- Done and phone-verified: Source details "Month by month" card (last 6 months, received/spent); More screen redesigned into grouped sections with icon tiles, subtitles and a live badge on Missed reminders.
- Next: empty states pass, Settings screen polish, form polish, remaining spec unit tests.
- flutter analyze clean, 133 tests pass.
- Phase 9 step 2 (phone-verified): Settings redesigned (grouped, icon tiles, app lock status line); `InlineEmpty` card replaces plain-text empty notes on account, source, subscription and person screens. Fingerprint loop fix confirmed on the phone. 133 tests pass.
- Phase 9 step 3: Save button pinned to the bottom (`SaveBar`) on the expense/income/transfer, account, source, due, subscription and category forms. New randomized invariant test (`test/ledger/ledger_invariants_test.dart`: 3 seeds x 120 mixed operations; source balances sum to account balance and allocations sum to amount after every step). 136 tests pass. Forms not yet looked at on the phone.
- iOS builds run on GitHub Actions (`.github/workflows/ios-build.yml`, macOS runner, no Mac needed): analyze, test, `flutter build ios --no-codesign`, unsigned .ipa artifact. Install by signing with Sideloadly/AltStore (free Apple ID, 7-day validity). iCloud backup needs a paid Apple Developer account (the iCloud container capability); everything else works without one. Not yet pushed to GitHub or run.
- Keyboard fix (reported on iPhone): `SaveBar` now sits above the keyboard (a Scaffold does not lift its bottom bar itself), has a Hide keyboard button, tapping blank space or dragging a form closes the keyboard. Widget test added. Not yet confirmed on a device.
- Reported: Home total includes money still to be received. Not reproduced; the total counts only recorded transactions (test `test/ledger/expected_money_test.dart`). Waiting for a screenshot of the Home screen.
