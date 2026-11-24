import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/database/seed.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds the built-in "Other money" source', () async {
    final sources = await db.select(db.incomeSources).get();
    expect(sources, hasLength(1));
    expect(sources.single.id, otherMoneySourceId);
    expect(sources.single.isBuiltIn, isTrue);
  });

  test('seeds expense and income categories', () async {
    final cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.kind == CategoryKind.expense), hasLength(11));
    expect(cats.where((c) => c.kind == CategoryKind.income), hasLength(5));
  });

  test('foreign keys are enforced', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.first, 1);
  });
}
