/// Enums stored as text in the database (via Drift `textEnum`).
/// Never rename a value without a migration.
enum SourceType { job, freelance, business, other }

enum PayScheduleType { monthly, weekly, everyNDays, irregular }

enum ActiveStatus { active, inactive }

enum AccountType { bank, mobileWallet, cash, onlineWallet, savings, other }

enum CategoryKind { expense, income }

enum TransactionType {
  income,
  expense,
  transfer,
  lendOut,
  borrowIn,
  repayIn,
  repayOut,
}

enum DueKind { expectedIncome, lent, borrowed }

enum DueEventType {
  created,
  payment,
  extended,
  note,
  reminderChanged,
  amountEdited,
  cancelled,
  settled,
  paymentEdited,
  paymentDeleted,
}

enum BillingUnit { day, week, month, year }

enum SubscriptionStatus { active, paused, cancelled }

enum ReminderRepeat { none, daily, weekly, monthly, everyNDays }
