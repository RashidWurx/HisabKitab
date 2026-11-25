import 'package:drift/drift.dart';

import 'enums.dart';

/// All money columns are integer paisa (rupees x 100). Never doubles.
/// Balances are NEVER stored; they are computed from transactions.

class IncomeSources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<SourceType>().withDefault(
    Constant(SourceType.other.name),
  )();
  TextColumn get linkedAccountId =>
      text().nullable().references(Accounts, #id)();
  IntColumn get expectedAmount => integer().nullable()();
  TextColumn get payScheduleType => textEnum<PayScheduleType>().nullable()();

  /// Day of month (monthly) or weekday 1..7 (weekly).
  IntColumn get payDay => integer().nullable()();

  /// For everyNDays schedules.
  IntColumn get payIntervalDays => integer().nullable()();

  /// Anchor date for everyNDays schedules.
  DateTimeColumn get payAnchorDate => dateTime().nullable()();
  TextColumn get status => textEnum<ActiveStatus>().withDefault(
    Constant(ActiveStatus.active.name),
  )();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF2E7D32))();
  TextColumn get iconKey => text().withDefault(const Constant('work'))();
  TextColumn get note => text().nullable()();

  /// True for the built-in "Other money" source (cannot be deleted/archived).
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<AccountType>().withDefault(
    Constant(AccountType.bank.name),
  )();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  TextColumn get defaultSpendingSourceId =>
      text().nullable().references(IncomeSources, #id)();
  TextColumn get status => textEnum<ActiveStatus>().withDefault(
    Constant(ActiveStatus.active.name),
  )();
  BoolColumn get includeInTotal =>
      boolean().withDefault(const Constant(true))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF1565C0))();
  TextColumn get iconKey => text().withDefault(const Constant('bank'))();
  TextColumn get note => text().nullable()();

  /// Savings goal (only used when type == savings).
  IntColumn get goalAmount => integer().nullable()();
  DateTimeColumn get goalDate => dateTime().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// How an account's opening balance is split across sources.
/// Any remainder not listed here counts as "Other money".
class AccountOpeningAllocations extends Table {
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get sourceId => text().references(IncomeSources, #id)();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {accountId, sourceId};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<CategoryKind>()();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF607D8B))();
  TextColumn get iconKey => text().withDefault(const Constant('category'))();
  TextColumn get defaultAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get defaultSourceId =>
      text().nullable().references(IncomeSources, #id)();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class People extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get defaultAccountId =>
      text().nullable().references(Accounts, #id)();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Dues extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get kind => textEnum<DueKind>()();
  TextColumn get personId => text().nullable().references(People, #id)();
  TextColumn get sourceId => text().nullable().references(IncomeSources, #id)();
  IntColumn get totalAmount => integer()();
  TextColumn get accountId => text().references(Accounts, #id)();

  /// Never changes after creation.
  DateTimeColumn get originalDueDate => dateTime()();

  /// Moves when the date is extended.
  DateTimeColumn get currentDueDate => dateTime()();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  IntColumn get reminderRepeatDays => integer().nullable()();
  TextColumn get note => text().nullable()();

  /// Set when the user cancels the due. Status itself is computed, never stored.
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  /// Amount written off when cancelled (counts as neither paid nor owed).
  IntColumn get writtenOffAmount => integer().withDefault(const Constant(0))();

  /// For auto-created payday dues: `sourceId:yyyy-MM-dd` to avoid duplicates.
  TextColumn get periodKey => text().nullable().unique()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Subscriptions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amount => integer()();
  TextColumn get billingUnit => textEnum<BillingUnit>()();

  /// Every N units (1 month, 3 months, 14 days, ...).
  IntColumn get billingEvery => integer().withDefault(const Constant(1))();
  DateTimeColumn get nextDueDate => dateTime()();

  /// Day of month the subscription was set up on (so a 31st billing day
  /// returns to the 31st after a short month). Added in schema v2.
  IntColumn get anchorDay => integer().nullable()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get reminderDaysBefore => integer().nullable()();
  TextColumn get status => textEnum<SubscriptionStatus>().withDefault(
    Constant(SubscriptionStatus.active.name),
  )();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_tx_date', columns: {#date})
@TableIndex(name: 'idx_tx_account', columns: {#accountId})
@TableIndex(name: 'idx_tx_to_account', columns: {#toAccountId})
@TableIndex(name: 'idx_tx_due', columns: {#dueId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<TransactionType>()();
  IntColumn get amount => integer()();

  /// Account money leaves (expense, transfer, lend_out, repay_out) or
  /// enters (income, borrow_in, repay_in). For transfers this is the FROM account.
  TextColumn get accountId => text().references(Accounts, #id)();

  /// Transfers only: the account the money goes to.
  @ReferenceName('incomingTransactions')
  TextColumn get toAccountId => text().nullable().references(Accounts, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get personId => text().nullable().references(People, #id)();
  TextColumn get dueId => text().nullable().references(Dues, #id)();
  TextColumn get subscriptionId =>
      text().nullable().references(Subscriptions, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which source's money a transaction moves. Rows for one transaction
/// always sum to the transaction amount (enforced in the repository layer).
@TableIndex(name: 'idx_alloc_tx', columns: {#transactionId})
@TableIndex(name: 'idx_alloc_source', columns: {#sourceId})
class TransactionAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceId => text().references(IncomeSources, #id)();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only history for dues. Only `note` events may be edited
/// (and then `editedAt` is set).
@TableIndex(name: 'idx_due_events_due', columns: {#dueId})
class DueEvents extends Table {
  TextColumn get id => text()();
  TextColumn get dueId => text().references(Dues, #id)();
  TextColumn get type => textEnum<DueEventType>()();
  DateTimeColumn get at => dateTime()();
  IntColumn get amount => integer().nullable()();
  TextColumn get accountId => text().nullable().references(Accounts, #id)();
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();
  DateTimeColumn get oldDate => dateTime().nullable()();
  DateTimeColumn get newDate => dateTime().nullable()();
  TextColumn get reason => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get editedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class CustomReminders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get amount => integer().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get accountId => text().nullable().references(Accounts, #id)();
  DateTimeColumn get remindAt => dateTime()();
  TextColumn get repeat => textEnum<ReminderRepeat>().withDefault(
    Constant(ReminderRepeat.none.name),
  )();
  IntColumn get repeatEveryDays => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Every notification the app asked the phone to show (past and upcoming).
/// Android never reports a missed or swiped-away notification, so the rows
/// whose time has passed and that the user has not handled yet ARE the
/// "Missed" inbox. [key] is stable across re-plans.
class NotificationLog extends Table {
  TextColumn get key => text()();
  IntColumn get notificationId => integer()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();

  /// Where it leads: `due:<id>`, `sub:<id>`, `reminder:<id>`, `backup`.
  TextColumn get payload => text()();
  DateTimeColumn get fireAt => dateTime()();

  /// A "remind me later" copy made by Snooze (kept even when the plan changes).
  BoolColumn get isSnooze => boolean().withDefault(const Constant(false))();

  /// Set when the user opened it, used one of its buttons, or dismissed it.
  DateTimeColumn get handledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Simple key/value store for app settings (not secrets; the PIN hash lives
/// in flutter_secure_storage).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
