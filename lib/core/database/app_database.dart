import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'enums.dart';
import 'seed.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    IncomeSources,
    Accounts,
    AccountOpeningAllocations,
    Categories,
    People,
    Dues,
    Subscriptions,
    Transactions,
    TransactionAllocations,
    DueEvents,
    CustomReminders,
    AppSettings,
    NotificationLog,
    PassThroughs,
    PassEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the on-device database file (`hisaab.sqlite`).
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'hisaab'));

  /// Bump this and add a step in [migration] for every schema change.
  /// Also run `dart run drift_dev schema dump` to save the new version.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDatabase(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: remember the billing day of a subscription.
        await m.addColumn(subscriptions, subscriptions.anchorDay);
        await customStatement(
          'UPDATE subscriptions SET anchor_day = CAST(strftime(\'%d\', next_due_date, \'unixepoch\', \'localtime\') AS INTEGER) WHERE anchor_day IS NULL',
        );
      }
      if (from < 3) {
        // v3: the notification log (missed-reminders inbox).
        await m.createTable(notificationLog);
      }
      if (from < 4) {
        // v4: 3rd party money.
        await m.createTable(passThroughs);
        await m.createTable(passEntries);
        await m.createIndex(idxPassEntriesPass);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
