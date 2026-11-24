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
12. **Visual design follows `designs/UI Screens/`** (5 reference mockups). Palette: cream `#F9F3E8` background, navy `#112E4E` primary (hero card `#183858`, mid `#2A4E76`, soft `#5C7C9F`), borders `#E6E0D8`, ink `#0B1F3A`. Green/red via `AppColors`. Outlined cards, 12-14px radius, full-width 52px navy buttons, bottom sheets with drag handle, "+" FAB centered over the nav. Dark mode is a navy version of the same palette. Match these mockups when building each screen.
11. **Schema snapshots** live in `drift_schemas/` for migration tests.
13. **Android build settings**: `compileSdk = 37` and core library desugaring are required by flutter_local_notifications. Gradle memory lowered to `-Xmx3G` (8G caused JVM/Dart crashes on this 16 GB PC).
14. **Package id** is `com.hisaab.hisaab`. An older app with the same id (higher version code) was on the test phone and was replaced on first install.

## 2026-11-25: Phase 2
15. **Inactive vs archived.** `status = inactive`: hidden from pickers (shown behind "Show inactive"), still in lists and always counted in balances. `isArchived`: also moved to an "Archived" section of the manager lists, hidden from pickers; still counted in balances. "Other money" can be neither.
16. **Account "money in / out" and period income/expense** count only `income` and `expense` transactions. Transfers and lend/borrow/repay change balances but are never income or expense. Account net = in - out; margin = net / in.
17. **Source "received / spent"** = income and expense allocations tagged to that source in the period; "left now" = the source's balance across all accounts.
18. **Balances in SQL.** One query unions allocation movements (+ for income/borrow_in/repay_in, - for expense/lend_out/repay_out, transfers - from / + to), opening splits, and the unsplit opening remainder tagged "Other money". An independent transactions-only query is tested to equal it.
19. **Editing amount**: one allocation follows the amount; if split, Save is disabled until the split is fixed. Edit previews exclude the transaction's own effect (`balancesWithout`).
20. **Delete + undo**: repository returns a snapshot (transaction + allocations); undo re-saves it.
21. **Deleting** an account/source/category with data is blocked and offers archive or move. Categories ask which category receives the transactions.
22. **Phase 4 items** (Lend, Borrow, Expected cash in) are disabled in quick add. Notification permission is requested in Phase 6, not onboarding.
23. **Settings** live in `app_settings` (`ask_source_each_expense`, `onboarding_done`, `month_start_day`, `theme_mode`). The router redirects to onboarding until `onboarding_done`.
24. **Git on Windows**: commit messages with here-strings must be sent from PowerShell (not Bash), otherwise a stray `@` ends up in the message.
