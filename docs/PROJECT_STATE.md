# Project State

_Last updated: 2026-11-25_

## Current phase
**Phase 4: Dues and people** is built (code, tests, committed). **Not yet verified on the phone**: the laptop restarted and the phone was disconnected. A crash seen while adding a person from the due form (`_dependents.isEmpty` assertion, caused by disposing a TextEditingController under a closing dialog) was fixed by `showTextDialog`, but the fix has not been re-tested on the device.

## Done
- Phases 1-3 (setup, ledger, money screens, dashboard).
- **Dues domain/data**: computed status (pending/partial/overdue/settled/cancelled), late days from the ORIGINAL date, partial payments, overpayment confirm, extend date (must be after today, unlimited, history), notes (editable with "edited"), snooze, cancel with write-off, delete, payment edit/delete with history entries, lent/borrowed create the lend_out/borrow_in transaction, repay_in goes back to the lending sources, track record and person net, rolling payday dues (31st rule), all with tests (63 tests total).
- **Screens**: Dues (To receive / To pay, status filter, People, one-tap "Received" on expected income), due detail with timeline, Mark received / Mark paid sheet, Extend date sheet, due form (Lend / Borrow / Expected cash in), People list, person form and person page (net, track record, history), source details (open dues, track record), account details (expected to arrive). Quick add tiles are now live.
- **Polish pass**: themes cached, theme switch is instant (no animation), router no longer reacts to unrelated settings, lazy Activity list with day totals, redesigned Home (gradient hero, quick actions, account cards, source cards with progress, upcoming), tinted icon tiles, avatars, soft card shadows, new Dues tiles.

## Next
1. Re-connect the phone, test Phase 4 flows on a RELEASE build (smoothness), fix issues.
2. Phase 5: Subscriptions, savings, custom reminders.

## Open items
- iOS parts tested later on a Mac. Google Cloud / Xcode steps go in the README in Phase 8.
- Month-by-month history on Source details still not built.
- Two Phase 1 commit messages start with a stray `@ `; history not rewritten.