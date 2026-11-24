# Hisaab: Offline Money Manager (Flutter)

Offline personal finance app for Android and iPhone, for people with several income sources. It shows where money comes from, which account it lands in, where it is spent, what is left, who owes what, and what is coming up. Reminders everywhere.

**Read first:** `docs/PROJECT_STATE.md` (where we are), `docs/FEATURE_MAP.md`, `docs/DECISIONS.md`, `docs/CONVENTIONS.md`. The full product spec is in `docs/SPEC.md`.

## Rules that never change
- 100% offline. All data is in a local SQLite (Drift) database. No server, no login, no analytics, no ads. The only internet use is manual backup/restore to the user's own Google Drive (Android) or iCloud (iPhone).
- Currency: PKR only. Show `Rs 12,500` (decimals only if present, negatives `-Rs 2,000`).
- Money is stored as integer paisa (amount x 100). Never `double` for money.
- Colour rule: positive / money in = green, negative / money out = red, everywhere, via `AppColors` (theme extension).
- Balances are always computed from transactions, never stored. All balances and totals (including per-source balances from allocations) come from one place (`LedgerService` / DAO queries). Never calculate money in widgets.
- Every transaction has allocations (`transaction_allocations`) that sum exactly to its amount. A transaction and its allocations are saved in one DB transaction.
- The sum of source balances in an account always equals that account's balance.
- Due status is computed from the current due date and payments, never stored. `due_events` is append-only (notes can be edited with an "edited" mark).
- Everything the user creates (sources, accounts, categories, people, transactions) can be edited, archived and deleted (with the edge-case rules in the spec, section 11).
- Use the device's local time zone for all dates and reminders.
- No runtime font downloads. System font or bundled asset only.

## Stack
Flutter (latest stable), Dart 3, Material 3 (`material_ui` imports, see DECISIONS), Riverpod, Drift, go_router, fl_chart, intl, flutter_local_notifications + timezone + flutter_timezone, local_auth, flutter_secure_storage, google_sign_in + googleapis, archive, share_plus, file_picker, path_provider, uuid.

Folder structure: feature-first `lib/features/<feature>/{data,domain,presentation}`, shared code in `lib/core/`.

## How to work
- The user is on Windows, builds for Android first. Write iOS parts (iCloud, notifications, Face ID) properly but do not block on them.
- The user is new to Git. Commit after every finished step with clear messages and run the git commands for them.
- Work phase by phase (see FEATURE_MAP.md). At the end of each phase: run `flutter analyze` and `flutter test`, update the docs, commit, give a short summary, and wait for the user's go.
- Check pub.dev for current package versions and APIs. Do not guess versions.
- After changing Drift tables: bump `schemaVersion`, add a migration step, run `dart run build_runner build`, then `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/`.
- Slash commands: `/checkpoint` saves progress to the docs and commits. `/pickup` reloads context at the start of a session.
