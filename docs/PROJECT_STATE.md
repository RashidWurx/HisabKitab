# Project State

_Last updated: 2026-11-25_

## Current phase
**Phase 5: Subscriptions, savings, custom reminders** is built and committed. Phases 4 and 5 (and the UI redesign + performance pass) are **not yet verified on the phone** because the PC cannot see the device (adb lists nothing). A release APK builds fine: `build/app/outputs/flutter-apk/app-release.apk`.

## Done
- Phases 1-4 (setup, ledger, money screens, dashboard, dues and people).
- **Schema v2**: `subscriptions.anchor_day` (keeps a 31st billing day after short months), with a tested v1 -> v2 migration and a schema snapshot.
- **Subscriptions**: list with monthly cost and paid-this-month, renewal countdowns, "Pay" sheet (amount editable) that creates a linked expense and moves the next date forward, pause/resume/cancel/delete, per-subscription history and spent this month/year/all time, form with idea chips (Spotify, Google One, iCloud, VPS, Warehouse).
- **Savings**: total saved, goal progress per savings account, Add to savings / Withdraw (pre-filled transfers), create savings account shortcut.
- **Custom reminders**: add/edit/delete, repeat (none/daily/weekly/monthly/every N days), active switch, "Pay" opens Add expense pre-filled; repeating reminders roll forward on app start/resume.
- 80 tests, `flutter analyze` clean.

## Next
1. Reconnect the phone and test phases 4-5 on a RELEASE build (also check dark/light switching speed).
2. Phase 6: Notifications (ReminderScheduler, per-type settings, overrides, tap to open the right screen).

## Open items
- Notification fields on subscriptions/dues are stored but nothing fires yet (Phase 6).
- Month-by-month history on Source details still not built.
- iOS parts tested later on a Mac. Google Cloud / Xcode steps go in the README in Phase 8.