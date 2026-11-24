# Project State

_Last updated: 2026-11-25_

## Current phase
**Phase 3: Dashboard** is complete and waiting for review. Verified on a TECNO KJ7: Home cards, money by source, accounts, upcoming, donut and income-vs-expense charts.

## Done
- Phases 1 and 2 (setup, theme, schema, ledger, accounts/sources/categories, forms, Activity, details, onboarding).
- **Dashboard** (`features/home`): `DashboardService` (due summary, per-source and per-account period rows, upcoming 7 days, 6-month totals), Home with total balance + savings, Income/Expense/Remaining, To receive / To pay (overdue count), Money by source, Accounts (in/out/expected), Upcoming, spending donut, income-vs-expense bars.
- Period switcher: This month, Last month, This year, Custom range, All time; the month start day setting (1-28) drives "month" everywhere (including the 6-month chart).
- Amount fields now only accept digits and up to 2 decimals.
- 38 tests, `flutter analyze` clean.

## Notes
- To receive / To pay, Expecting and Upcoming dues read the `dues` table already, so they light up by themselves when Phase 4 creates dues. Until then they show Rs 0 / "Nothing due".
- Source rows on Home show Received and Spent for the chosen period, and "Left" = the source's money across all accounts right now (same as Source details).

## Next
Phase 4: Dues and people (expected cash in, lent, borrowed, Mark received with partial payments, statuses, extend date, history timeline, track record, person page, payday dues).

## Open items
- Custom date range and the period menu were tested in code (unit tests) but not tapped through on the phone.
- Month-by-month history on Source details is still not built.
- iOS parts will be tested later on a Mac. Google Cloud / Xcode steps go in the README in Phase 8.
- Two Phase 1 commit messages start with a stray `@ `; history not rewritten.