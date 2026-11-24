# Feature Map

| Phase | Scope | Status |
|---|---|---|
| 1 | Setup: project, git, docs, theme, router, Drift schema, seeds | Done |
| 2 | Money basics: accounts, sources, categories, expense/income/transfer, allocations (auto-pick, split), Activity + filters, account/source details, onboarding | Done |
| 3 | Dashboard: Home cards, Money by source, period switcher, month start day, charts | Done |
| 4 | Dues and people: expected/lent/borrowed, partial payments, statuses, extend date, history, track record, person page, payday dues | Built, awaiting phone test |
| 5 | Subscriptions, savings, custom reminders | Built, awaiting phone test |
| 6 | Notifications: ReminderScheduler, per-type settings, overrides, deep links | Built, background delivery needs phone setting |
| 7 | App lock (PIN, biometrics) | Not started |
| 8 | Backup and restore: local export/import, Google Drive, iCloud | Not started |
| 9 | Polish and tests | Not started |

## Database tables (schema v1)
`income_sources`, `accounts`, `account_opening_allocations`, `categories`, `people`, `dues`, `subscriptions`, `transactions`, `transaction_allocations`, `due_events`, `custom_reminders`, `app_settings`.

## Code map
- `lib/core/database/`: tables, enums, `AppDatabase`, seed, provider
- `lib/core/theme/`: `AppTheme`, `AppColors`
- `lib/core/router/`: go_router config
- `lib/core/utils/money.dart`: paisa formatting/parsing
- `lib/features/shell/`: bottom-nav shell, placeholder page

## Code map (Phase 2 additions)
- `lib/core/providers.dart`: Riverpod providers (repositories, streams, balances)
- `lib/core/ui/`: shared widgets (`MoneyText`, `AppCard`, `IconBox`, `PickerField`, `AmountField`, pickers, `ManagedList`)
- `lib/core/utils/period.dart`: period ranges with month start day
- `lib/features/ledger/`: `LedgerService`
- `lib/features/transactions/`: repository, domain (models, allocation logic), forms, split sheet, activity
- `lib/features/accounts|sources|categories/`: data + presentation
- `lib/features/settings|onboarding|more|home|shell/`

- `lib/features/home/`: dashboard service, Home page, charts, period state
