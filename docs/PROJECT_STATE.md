# Project State

_Last updated: 2026-11-25_

## Current phase
**Phase 2: Money basics** is complete and waiting for review. Verified on a TECNO KJ7 (Android 14): onboarding, Home, quick add, add expense, Activity, account details.

## Done
- Phase 1 (setup, theme from `designs/UI Screens/`, router, Drift schema v1, seeds).
- **Ledger layer** (`features/ledger`, `features/transactions/data|domain`): `LedgerService` (per-account-per-source balances in one SQL query, independent transactions-only balance check, period totals, spending by category, source stats), `TransactionRepository` (validation + save/delete/undo in one DB transaction), auto-pick and split logic, 18 ledger tests.
- Repositories for accounts, sources, categories, settings with delete rules (blocked + archive or move).
- Screens: onboarding (3 skippable steps), Home (basic total + accounts), Activity (search, filters, swipe delete with undo, edit), quick add sheet, add/edit expense/income/transfer, split-by-source sheet, accounts/sources/categories managers (add, edit, reorder, archive, delete), account details, source details, More, Settings (ask-source toggle, month start day, theme, run setup again, delete all data).
- 30 tests, `flutter analyze` clean.

## Not in Phase 2 (by design)
- Lend, Borrow, Expected cash in tiles are shown disabled in quick add (Phase 4). Open dues / expected deposits on detail screens come with Dues.
- Source details: month-by-month history is not built yet (Phase 3/9).
- Notification permission request moved to Phase 6.
- People, Savings, Custom reminders, Backup rows in More are placeholders.

## Next
Phase 3: Dashboard (Home cards, Money by source, period switcher with custom range, month start day wiring, charts).

## Open items
- iOS parts will be tested later on a Mac.
- Google Cloud / Xcode setup steps go in the README in Phase 8.
- Two Phase 1 commit messages start with a stray `@ ` (shell quoting slip); history was not rewritten.
