# Project State

_Last updated: 2026-11-24_

## Current phase
**Phase 1: Setup** is complete and waiting for review.

## Done
- Flutter project (Flutter 3.50.0 / Dart 3.14.0), Android + iOS platforms, git repo.
- `CLAUDE.md`, docs, `/checkpoint` and `/pickup` commands.
- Material 3 theme (light/dark) with `AppColors` (green/red/status colours), `Money` formatter/parser.
- go_router with 5-tab shell (Home, Activity, Dues, Subscriptions, More), placeholder screens.
- Drift database, schema v1, all tables, foreign keys on, seeds (Other money source + categories), schema dumped to `drift_schemas/`.
- Tests: money format/parse, seeding, foreign keys.

- Theme restyled to match `designs/UI Screens/` (cream + navy). Phone: TECNO KJ7 (Android 14) connected over USB for testing; first debug run verified: app launches, 5-tab nav renders correctly.

## Next
Phase 2: Money basics (accounts, sources, categories, add/edit expense/income/transfer, allocations with auto-pick and split, Activity, detail screens, onboarding).

## Open items
- iOS parts will be tested later on a Mac.
- Google Cloud / Xcode setup steps go in the README in Phase 8.
