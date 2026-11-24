# Decisions

## 2026-11-24: Phase 1
1. **`material_ui` imports.** Flutter 3.50 split Material into the `material_ui` package and the `flutter create` template imports it. We follow the template.
2. **Plain Riverpod providers, no code generation.** Dropped `riverpod_generator`. Less build time and fewer moving parts. Drift still uses build_runner.
3. **IDs are text UUIDs** (uuid package), except fixed ids for seeds (`other_money`, `cat_exp_*`, `cat_inc_*`).
4. **Enums stored as text** (`textEnum`) so backups and migrations stay readable. Never rename an enum value without a migration.
5. **Transfers** use `accountId` (from) and `toAccountId` (to). Allocations carry the source of the money out of the from account and into the to account.
6. **Opening balance split** lives in `account_opening_allocations`; any unsplit remainder counts as "Other money".
7. **Dues**: `periodKey` (unique) prevents duplicate payday dues. Status is computed. `cancelledAt` + `writtenOffAmount` record cancellation.
8. **Amounts in the UI are 1 rupee = 100 paisa**, parsed with up to 2 decimals.
9. **Number grouping**: standard `12,500` / `1,250,000` (not lakh grouping), as in the spec example.
10. **sqlite3 comes through `drift_flutter`**; the old `sqlite3_flutter_libs` plugin is end-of-life and not a direct dependency.
11. **Schema snapshots** live in `drift_schemas/` for migration tests.
