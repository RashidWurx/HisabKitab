import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../transactions/data/transaction_repository.dart';

class CategoryDraft {
  const CategoryDraft({
    this.id,
    required this.name,
    required this.kind,
    required this.colorValue,
    required this.iconKey,
    this.defaultAccountId,
    this.defaultSourceId,
  });

  final String? id;
  final String name;
  final CategoryKind kind;
  final int colorValue;
  final String iconKey;
  final String? defaultAccountId;
  final String? defaultSourceId;
}

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Category>> watchAll() => (_db.select(
    _db.categories,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).watch();

  Future<String> save(CategoryDraft d) async {
    if (d.name.trim().isEmpty) throw LedgerException('Enter a name.');
    final id = d.id ?? _uuid.v4();
    final existing = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    final max = _db.categories.sortOrder.max();
    final row = await (_db.selectOnly(_db.categories)..addColumns([max]))
        .getSingle();
    await _db
        .into(_db.categories)
        .insertOnConflictUpdate(
          CategoriesCompanion(
            id: Value(id),
            name: Value(d.name.trim()),
            kind: Value(d.kind),
            colorValue: Value(d.colorValue),
            iconKey: Value(d.iconKey),
            defaultAccountId: Value(
              d.kind == CategoryKind.expense ? d.defaultAccountId : null,
            ),
            defaultSourceId: Value(
              d.kind == CategoryKind.expense ? d.defaultSourceId : null,
            ),
            isArchived: Value(existing?.isArchived ?? false),
            sortOrder: Value(existing?.sortOrder ?? (row.read(max) ?? 0) + 1),
          ),
        );
    return id;
  }

  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (var i = 0; i < idsInOrder.length; i++) {
      await (_db.update(_db.categories)
            ..where((c) => c.id.equals(idsInOrder[i])))
          .write(CategoriesCompanion(sortOrder: Value(i)));
    }
  });

  Future<void> setArchived(String id, bool archived) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(isArchived: Value(archived)),
      );

  Future<int> usageCount(String id) async {
    final c = _db.transactions.id.count();
    final row =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([c])
              ..where(_db.transactions.categoryId.equals(id)))
            .getSingle();
    return row.read(c) ?? 0;
  }

  /// Deletes a category. If it is used, [moveToId] (same kind) is required
  /// and receives its transactions, subscriptions and reminders.
  Future<void> delete(String id, {String? moveToId}) async {
    final used = await usageCount(id);
    if (used > 0 && moveToId == null) {
      throw LedgerException('Choose a category to move its transactions to.');
    }
    if (moveToId == id) throw LedgerException('Choose a different category.');
    await _db.transaction(() async {
      if (moveToId != null) {
        await (_db.update(_db.transactions)
              ..where((t) => t.categoryId.equals(id)))
            .write(TransactionsCompanion(categoryId: Value(moveToId)));
        await (_db.update(_db.subscriptions)
              ..where((s) => s.categoryId.equals(id)))
            .write(SubscriptionsCompanion(categoryId: Value(moveToId)));
        await (_db.update(_db.customReminders)
              ..where((r) => r.categoryId.equals(id)))
            .write(CustomRemindersCompanion(categoryId: Value(moveToId)));
      } else {
        await (_db.update(_db.subscriptions)
              ..where((s) => s.categoryId.equals(id)))
            .write(const SubscriptionsCompanion(categoryId: Value(null)));
        await (_db.update(_db.customReminders)
              ..where((r) => r.categoryId.equals(id)))
            .write(const CustomRemindersCompanion(categoryId: Value(null)));
      }
      await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
    });
  }
}
