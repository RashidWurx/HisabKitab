# Hisaab: Product Spec (saved from the original build prompt)

Offline personal finance app (Flutter, Android first, iOS written properly but tested later on a Mac) for people with more than one income source. Shows where money comes from, which account it lands in, where it is spent, what is left, who owes what, what is coming up. Reminders everywhere.

## 1. Rules that never change
- 100% offline, local DB. No server, login, analytics, ads. Only internet use: manual backup/restore to the user's own Google Drive (Android) or iCloud (iPhone).
- PKR only. `Rs 12,500`.
- Positive / money in = green, negative / money out = red, everywhere.
- Full control: sources, accounts, categories, people can be added, edited, archived, reordered. Every record can be edited or deleted.

## 3. Core concepts
**Income Source**: name, type (job, freelance, business, other), linked account, expected amount (optional), pay schedule (optional: monthly on day X, weekly, every N days, irregular), status (active/inactive), color, icon, note. Not a place money sits. App always knows how much of each source's money is left and in which accounts. Inactive: no payday reminders, "Inactive" badge.

**Account**: name, type (bank, mobile wallet, cash, online wallet, savings, other), opening balance (can be split across sources), default spending source, status, include in total balance, color, icon, note. Balance = opening + in - out, always computed from transactions. One account can be linked to many sources; balance is split by source.

**Category**: separate expense and income. Each expense category can have a default account and default source (pre-select on add expense, changeable). Seed expense: Family, Siblings, Petrol, Packages, Food, Bills, Rent, Shopping, Health, Subscriptions, Other. Seed income: Salary, Freelance, Sales, Gift, Other.

**Person**: name, phone, note, default account for receiving money.

**Transaction types**: `income` (optional source/category), `expense` (category required), `transfer` (A to B, not income/expense), `lend_out` (linked to lent due), `borrow_in` (borrowed due), `repay_in` (lent due), `repay_out` (borrowed due). Can link category, person, due, subscription. lend/borrow/repay change balances but are not income or expense in totals.

**Spending by source**: every rupee carries a source tag. Built-in source "Other money" (cannot be deleted/archived). Every transaction has allocations (`transaction_allocations`: transaction id, source id, amount) that sum to the amount.
- income: one allocation to its source.
- expense / subscription payment / lend_out / repay_out: whose money was used; can split (Rs 10,000 rent = 6,000 Job 1 + 4,000 Freelancing).
- transfer: source tag moves with the money.
- borrow_in: "Other money" by default (changeable). repay_in: back to the source the lent money came from (changeable).
- Opening balance: can split across sources; rest = "Other money".
- Balances computed: source money left in account = its money in - its money out (transfers included). Overall = sum across accounts. Sum of source balances in an account = account balance.
- Auto-pick source order: (1) category default source if it has money in that account, (2) account default spending source, (3) source with most money in that account. Shown as a chip under the account field; tap to change or split.
- Shortfall: if expense > picked source's money in that account, show shortfall in red; offer "Split with another source" (auto-fills from next source with money) or "Save anyway" (source goes negative in this account, red).
- Setting "Ask which source on every expense" (default on). Off: picker hidden, auto-pick runs silently.

**Due**: kinds `expected_income`, `lent` (creating also records lend_out), `borrowed` (creating also records borrow_in). Fields: title, kind, person (optional for expected_income, required for lent/borrowed), source, total, account, original due date (never changes), current due date, reminder (date+time, optional repeat every N days until settled), note. Every due has an account; auto-fill order: source's linked account, person's default account, last used account.
- "Mark received/paid" sheet: remaining prefilled, custom amount, account and date changeable; less than remaining = partial. Multiple payments, each with own date/amount/account. Show total, received/paid, remaining. Overpayment: warn and confirm. Quick actions: Mark received/paid, Extend date, Add note, Snooze reminder, Cancel.
- Extend date: new date (required, after today), reason (optional but asked), new reminder (default 1 day before and on new date). Original date kept forever. Status returns to pending/partial; overdue again if new date passes. Unlimited extensions. Show "Extended 2x" and "Late by X days" (from original date). "Add note" any time.
- `due_events` append-only: created, payment (amount, account), extended (old to new, reason), note, reminder changed, amount edited, cancelled, settled. Timeline newest on top.
- Person page and source details show track record: paid on time vs late, average days late.
- Status computed: pending, partial, overdue (current due date passed and remaining > 0), settled, cancelled (ask whether to write off remaining).
- Person page: what they owe you, what you owe them, net, history.

**Paydays**: a source with a pay schedule auto-creates an `expected_income` due per period ("Job 1 salary, Dec 2026") into its linked account with a reminder on payday. One tap confirm, amount editable. Rolling: only the next period's due is created ahead.

**Subscription**: name, amount, billing cycle (weekly, monthly, yearly, every N days/months), next due date, pay-from account, category (default Subscriptions), reminder days before, status (active/paused/cancelled), note. Mark paid creates an expense linked to the subscription and moves next due date; amount editable. Show monthly cost of active subscriptions (yearly / 12), spent this month/year/all time, per-subscription history. Empty state hints: Spotify, Google One, iCloud, VPS, Warehouse.

**Savings**: an account of type `savings` + optional goal (target amount, date). Savings screen: total saved, each account with progress bar. "Add to savings" = transfer in; "Withdraw" = transfer out.

**Custom reminders**: title, amount, category + account, date/time, repeat (none, daily, weekly, monthly, every N days). Tap can open Add Expense pre-filled.

## 4. Screens
Bottom nav: Home, Activity, Dues, Subscriptions, More. Center "+" on Home and Activity. Quick add: Expense, Income, Transfer, Lend, Borrow, Expected cash in.

**Home**: period switcher (This month default, Last month, This year, Custom, All time); month start day setting (1-28). Cards: Total income, Total expense, Remaining (green/red). Total balance (include-in-total accounts), savings total separate. To receive (expected_income + lent remaining, overdue count red) and To pay (borrowed). Money by source for the period: received, spent, left, still expected and which account. Accounts list: balance, in/out for period, expected coming. Upcoming 7 days. Charts (fl_chart): spending by category, income vs expense last 6 months.

**Activity**: transactions grouped by day, search + filters (type, account, source, category, person, date range). Tap to edit. Swipe delete with undo.

**Forms**: big amount field, number keypad, autofocus. Expense: amount, category icon grid, account (from category default), source chip, date, note, person; show account balance and source money left after; red + warning if below 0 but can save. Income: amount, source, account (source's linked), category, date, note. Transfer: from, to (not same), amount, source chip, date, note. Lend/Borrow/Expected: follow Due rules.

**Account details**: balance, split by source, in, out, net, margin % (net / in), linked sources, expected coming, spending by category, transactions. **Source details**: linked account, schedule, received/spent/left, where its money is now, spending by category, expected vs received, month history, open dues, active toggle.

**Dues**: tabs To receive / To pay. Items show title, person/source, total, received, remaining, due date, status chip (pending amber, partial blue, overdue red, settled green), "Late by X days", "Extended 2x". Overdue on top. Status filter. People list reachable from here. **Subscriptions**: list, monthly total, history. **More**: Accounts, Income sources, Savings, People, Categories, Custom reminders, Settings, Backup & restore.

**Settings**: manage sources/accounts/categories/people (add, edit, reorder, archive, delete); "Ask which source" toggle; notifications; app lock; backup; month start day; theme (light/dark/system); run setup again; danger zone delete all data (double confirm).

**Onboarding** (3 skippable steps): accounts with balances; income sources linked to accounts; pick categories. Then ask notification permission.

## 5. Notifications
flutter_local_notifications + timezone + flutter_timezone. Types, each with own settings (on/off, default time, default days before): paydays, expected cash in follow-ups, money you owe, money owed to you, subscriptions, custom reminders, overdue nudges (every day or N days), backup reminder (no backup in N days, default 7). Default for dues/paydays: 1 day before and on due date. Per-item override. Tap opens right screen (payload + go_router). Due/payday notifications have actions "Received" (opens Mark received sheet) and "Extend". iOS limit 64 pending: one `ReminderScheduler` runs on app start, resume and after data change: cancel all, schedule nearest 60. Android: POST_NOTIFICATIONS on 13+, `inexactAllowWhileIdle`, survive reboot. Short text, e.g. "Ali owes you Rs 5,000. Due today."

## 6. App lock (optional)
4-6 digit PIN, optional fingerprint/Face ID (local_auth). Store only salted hash in flutter_secure_storage. Lock after background: immediately / 1 min / 5 min. Hide content in recents. Forgot PIN: only way out is reset app data and restore a backup; say so clearly when setting PIN.

## 7. Backup and restore (manual)
Zip with SQLite DB (`VACUUM INTO`) + `manifest.json` (app version, schema version, created at, device name, record counts). Name `hisaab_backup_YYYY-MM-DD_HHmm.zip`. Android: Google Drive via google_sign_in + googleapis with `drive.appdata` scope; README has Google Cloud setup (OAuth client, SHA-1). iPhone: iCloud container (plugin or Swift method channel); README has Xcode setup. Both: Export (share sheet) and Import (file picker). Screen: Back up now, last backup date/time/size, list of cloud backups (keep latest 10), restore any. Restore: check manifest, run migrations if older, show what will be replaced, confirm, close DB, swap file, reopen, rebuild reminders. Never restore a newer schema. Clear errors: no internet, sign-in cancelled, not enough storage, damaged file.

## 8. Tech
Flutter, Dart 3, Material 3, Riverpod, Drift with migrations from day 1, go_router, paisa ints, intl, fl_chart. No runtime font downloads. Feature-first folders. All money from `LedgerService`/DAO. Transaction + allocations in one DB transaction.

## 9. Design
Clean, simple, big numbers. Green/red rule. Status chips. Light/dark. Friendly empty states with action buttons. `Rs 12,500`, `-Rs 2,000` in red. Icon + color pickers for sources, accounts, categories. Light animations, fast on low-end Android.

## 10. Phases (stop after each for review)
1. Setup. 2. Money basics. 3. Dashboard. 4. Dues and people. 5. Subscriptions, savings, custom reminders. 6. Notifications. 7. App lock. 8. Backup and restore (local first, then Drive, then iCloud). 9. Polish and tests (balances, allocations incl. splits/transfers/repay_in source, due status, extensions, pay schedule dates, subscription next date, backup round trip).

## 11. Edge cases
- Delete account/source with transactions: block, offer archive or move.
- Delete source with tagged money: block, offer archive or move allocations (or "Other money").
- Delete category: ask which category to move transactions to.
- Edit transaction amount: one allocation updates too; split requires user to fix split first.
- Edit/delete a payment updates due status immediately and adds a history entry.
- History never edited/deleted, only added (notes editable with "edited" mark).
- Extended date must be after today.
- Inactive account: hidden from pickers (with "show inactive" toggle), still counted in balances.
- No transfer to same account. Amounts > 0.
- Payday on 31st in a 30-day month falls on last day.
- Device local time zone for all dates/reminders.

## 12. Done means
Works offline (airplane mode). Money numbers match on Home, Account details, Source details, Activity, Dues. Per account, source balances sum to account balance. Reminders fire on a real Android phone and survive reboot. Back up, uninstall, reinstall, restore brings everything back incl. reminders. `flutter analyze` clean, tests pass.
