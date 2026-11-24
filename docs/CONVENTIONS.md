# Conventions

## Code
- Feature-first: `lib/features/<feature>/{data,domain,presentation}`; shared code in `lib/core/`.
- Money is `int` paisa. Format with `Money.format`, parse with `Money.parse`. No `double` money, ever.
- No money maths in widgets. Balances and totals come from `LedgerService` / DAO queries.
- Colours: use `context.appColors` (positive/negative/pending/partial/overdue/settled). Never hard-code green/red.
- Saving a transaction + allocations = one `db.transaction(...)`.
- Dates use the device's local time zone. Due dates are date-only in meaning (store midnight local).
- Riverpod providers are plain (`Provider`, `StreamProvider`, `NotifierProvider`), no codegen.
- Imports: `package:material_ui/material_ui.dart` for Material widgets.

## Database
- Change a table: bump `schemaVersion`, add an `onUpgrade` step, run `dart run build_runner build`, then `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/`.
- Never store balances or due status.

## Git
- One commit per finished step. Message style: `phase N: short description` (imperative, lower-case after the colon).
- Do not commit `build/`, `.dart_tool/`, secrets, keystores or `google-services` files.

## Quality gate (end of every phase)
`flutter analyze` clean, `flutter test` passing, docs updated, committed.

## UI
- Big readable numbers, light animations, friendly empty states with an action button.
- Status chips: pending amber, partial blue, overdue red, settled green.
