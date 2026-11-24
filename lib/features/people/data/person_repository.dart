import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';

class PersonDraft {
  const PersonDraft({
    this.id,
    required this.name,
    this.phone,
    this.note,
    this.defaultAccountId,
  });

  final String? id;
  final String name;
  final String? phone;
  final String? note;
  final String? defaultAccountId;
}

class PersonRepository {
  PersonRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<PeopleData>> watchAll() => (_db.select(
    _db.people,
  )..orderBy([(p) => OrderingTerm.asc(p.sortOrder)])).watch();

  Future<PeopleData?> get(String id) =>
      (_db.select(_db.people)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<String> save(PersonDraft d) async {
    if (d.name.trim().isEmpty) throw LedgerException('Enter a name.');
    final id = d.id ?? _uuid.v4();
    final existing = await get(id);
    final max = _db.people.sortOrder.max();
    final row = await (_db.selectOnly(_db.people)..addColumns([max]))
        .getSingle();
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    await _db
        .into(_db.people)
        .insertOnConflictUpdate(
          PeopleCompanion(
            id: Value(id),
            name: Value(d.name.trim()),
            phone: Value(clean(d.phone)),
            note: Value(clean(d.note)),
            defaultAccountId: Value(d.defaultAccountId),
            isArchived: Value(existing?.isArchived ?? false),
            sortOrder: Value(existing?.sortOrder ?? (row.read(max) ?? 0) + 1),
            createdAt: Value(existing?.createdAt ?? DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (var i = 0; i < idsInOrder.length; i++) {
      await (_db.update(_db.people)..where((p) => p.id.equals(idsInOrder[i])))
          .write(PeopleCompanion(sortOrder: Value(i)));
    }
  });

  Future<void> setArchived(String id, bool archived) =>
      (_db.update(_db.people)..where((p) => p.id.equals(id))).write(
        PeopleCompanion(isArchived: Value(archived)),
      );

  /// Deleting is blocked when the person has dues or transactions
  /// (archive them instead).
  Future<void> delete(String id) async {
    final dues = _db.dues.id.count();
    final d =
        await (_db.selectOnly(_db.dues)
              ..addColumns([dues])
              ..where(_db.dues.personId.equals(id)))
            .getSingle();
    final txs = _db.transactions.id.count();
    final t =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([txs])
              ..where(_db.transactions.personId.equals(id)))
            .getSingle();
    if ((d.read(dues) ?? 0) + (t.read(txs) ?? 0) > 0) {
      throw BlockedDeleteException(
        'This person has dues or transactions. Archive them instead.',
      );
    }
    await (_db.delete(_db.people)..where((p) => p.id.equals(id))).go();
  }
}
