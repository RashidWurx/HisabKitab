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

## 2026-11-25: Phase 3
25. **Home "Left" per source** is the source's current total across accounts (not period received - spent), so it always matches Source details and the account split. Received/Spent are for the selected period.
26. **Dues maths lives in SQL** (`DashboardService`): remaining = total - written off - payments, where payments are `income`/`repay_in`/`repay_out` linked to the due. The `lend_out`/`borrow_in` that creates a due is not a payment. Cancelled dues are excluded. Overdue = current due date before today and remaining > 0.
27. **Upcoming (7 days)** includes overdue dues, active subscriptions and active custom reminders; lent/expected are green, borrowed/subscriptions/reminders are red.
28. **Charts** use fl_chart; the donut keeps the 5 biggest categories and folds the rest into "Other categories". Bars are the last 6 month-periods (respecting the month start day).
29. **Amount inputs** are filtered to `digits[.dd]` so commas and stray characters cannot be typed.
## 2026-11-25: Phase 4 and polish
30. **Due reminders**: `reminderAt = null` means "use the defaults (1 day before and on the due date)"; a non-null value is a per-item override. Extending a date resets the override unless a custom one is chosen.
31. **Deleting a payment** keeps its history entry but cuts the link to the deleted transaction (`due_events.transaction_id` set to null). Deleting a due removes its history and linked transactions (balances change; the UI confirms).
32. **Dues created from Activity**: transactions linked to a due open the due on tap and cannot be swiped away in Activity.
33. **Paydays**: `PaydayService` runs on start, on app resume and when sources change; one due per source per period (`periodKey`); needs an expected amount and a linked account.
34. **Performance rules**: cache `ThemeData`, `themeAnimationDuration: Duration.zero`, `InkRipple`, router listens only to the onboarding flag, lazy lists for long data, `RepaintBoundary` on charts, chart animations off. Judge smoothness on a release build, not debug.
35. **Dialogs with text fields** must use `showTextDialog` (the controller lives in the dialog's State). Never dispose a controller right after `await showDialog`.
## 2026-11-25: Phase 5
36. **Subscription dates** use the original billing day (`anchor_day`), so 31 Jan -> 28 Feb -> 31 Mar. Marking paid moves the date forward exactly one cycle from the paid due date.
37. **Subscription "this month"** follows the month start day setting.
38. **Monthly cost**: yearly / 12, weekly x 52 / 12, daily x 365 / 12, "every N" divides by N; rounded to whole paisa; only active subscriptions count.
39. **Deleting a subscription** keeps its expenses (they lose the link). Marking paid uses the subscription's category, else the "Subscriptions" category, else the first expense category.
40. **Savings** is the existing savings account type + goal on the account; "Add to savings" / "Withdraw" are transfers opened with `?to=` / `?from=`.
41. **Reminder pre-fill**: `/transaction/new/expense?amount=<paisa>&category=..&account=..`.
## 2026-11-25: Phase 6
42. **ReminderScheduler** = pure planner (`planReminders`, tested) + plugin wrapper. It re-plans on app start, on resume and (debounced 1.2 s) after any change to dues, subscriptions, reminders, sources, accounts, people or settings; it cancels only PENDING notifications, then schedules the nearest 60. Android uses `inexactAllowWhileIdle` (no exact-alarm permission); the plugin's boot receiver re-creates alarms after a reboot.
43. **Defaults**: 9:00 AM, 1 day before and on the day (dues, paydays, subscriptions); overdue nudges daily from the day after the due date (3 ahead); backup reminder after 7 days; each due can override with its own date/time and repeat; each subscription with its own days-before; custom reminders use their own time.
44. **Tap routing**: payload `due:<id>` / `sub:<id>` / `reminder:<id>` / `backup` / `test`. Due notifications have "Received" and "Extend" buttons that open the Mark received / Extend sheets. A reminder with an amount/category/account opens Add expense pre-filled.
45. **Phone-specific**: on TECNO/HiOS (and similar) a scheduled notification arrived while the app was in the foreground but NOT while it was in the background, even with battery optimisation off. The Notifications screen explains this and links to the app's system settings (battery, autostart). The user must allow background activity for reliable reminders.
## 2026-11-25: Phase 7
46. **App lock** keeps everything in `flutter_secure_storage` (flag, timeout, biometrics, PIN length, salt, PBKDF2-HMAC-SHA256 hash with 10,000 iterations), not in the database, so a restored backup can never bring back a lock whose PIN is gone; an "enabled" flag without a hash counts as off.
47. **Lockout**: first 4 wrong PINs free, then 30 s, 1 min, 5 min, 15 min, 1 h. Success resets the counter.
48. **Lock timing**: immediately / after 1 minute / after 5 minutes of being in the background (`shouldLockOnResume`). System dialogs and the biometric prompt are ignored for locking.
49. **Hidden in recents**: Android `FLAG_SECURE` through the `hisaab/privacy` channel while the lock is on (this also blocks screenshots and `adb screencap`), plus a navy cover whenever the app is inactive.
50. **Forgot PIN** = erase all data and the PIN (double confirm) and then restore a backup. "Delete all data" in Settings also removes the PIN.
51. `MainActivity` is a `FlutterFragmentActivity` (needed by local_auth) and the launch themes use AppCompat.
## 2026-11-26: period, borrowed money, planned payments
52. **Home period is saved** (`home_period` setting: a `PeriodKind` name or `custom:<start>:<end>`). Account and source detail pages keep their own temporary period.
53. **Home total = money in accounts minus open borrowed dues** (`LedgerService.netBalance`), so it can be negative. Account balances, allocations and the `borrow_in` transaction are unchanged. A line under the total shows both numbers while something is owed.
54. **A custom reminder with an amount is a planned payment.** No expense exists until the user records it ("Paid" opens Add expense pre-filled; `ReminderRepository.recordPaid` saves the expense and closes that occurrence in one DB transaction). It never rolls forward by itself, stays in Upcoming while unpaid, and is nudged using the overdue settings. Notification payload `pay:<id>`. Planned payments are not part of the Home total or the "To pay" amount.

## 2026-11-27: 3rd party money
55. **Money borrowed from one person for another** is its own record (`pass_throughs` + `pass_entries`, schema v4), not a due. Chosen with the user: it can travel through an account or straight between the two; it shows in its own Home card; paying the lender before collecting is allowed (the other person then owes the user); returns can be in parts, with separate "collect by" and "return by" dates.
56. Account movements are transactions of type `passIn` / `passOut` (never income, expense or dues). Their money is tagged "Other money"; when the user's own money covers a payment it comes from real sources and returns to them when collected.
57. **Home total also subtracts 3rd party money being held** (per record, only accounts included in the total). Money the user covered is not added back until collected.
58. Mistakes are fixed by removing a history step or deleting the record. The first step and (after any return) the amount cannot be edited. Reminders use the "owed to you" / "you owe" and overdue settings; payload `pass:<id>`.
