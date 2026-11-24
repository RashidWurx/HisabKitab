import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';

import '../generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('migrating v1 -> v2 keeps data and fills the subscription anchor day',
      () async {
    final schema = await verifier.schemaAt(1);
    final due = DateTime(2026, 12, 25, 12).millisecondsSinceEpoch ~/ 1000;
    final created = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
    schema.rawDatabase.execute(
      "INSERT INTO accounts (id, name, created_at) VALUES ('a', 'Meezan', $created)",
    );
    schema.rawDatabase.execute(
      "INSERT INTO subscriptions (id, name, amount, billing_unit, next_due_date, account_id, created_at) "
      "VALUES ('s', 'Spotify', 110000, 'month', $due, 'a', $created)",
    );

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    final rows = await db
        .customSelect('SELECT name, anchor_day FROM subscriptions')
        .get();
    expect(rows.single.read<String>('name'), 'Spotify');
    expect(rows.single.read<int>('anchor_day'), 25);
    final accounts = await db.select(db.accounts).get();
    expect(accounts.single.name, 'Meezan');
    await db.close();
  });
}