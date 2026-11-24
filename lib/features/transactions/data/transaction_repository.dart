import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../domain/allocation_logic.dart';
import '../domain/transaction_models.dart';

/// A rule was broken (bad amount, split does not add up, ...).
/// The message is safe to show to the user.
class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TransactionFilter {
  const TransactionFilter({
    this.search = '',
    this.types = const {},
    this.accountId,
    this.sourceId,
    this.categoryId,
    this.personId,
    this.from,
    this.to,
  });

  final String search;
  final Set<TransactionType> types;
  final String? accountId;
  final String? sourceId;
  final String? categoryId;
  final String? personId;
  final DateTime? from;

  /// Exclusive upper bound.
  final DateTime? to;

  bool get isEmpty =>
      search.isEmpty &&
      types.isEmpty &&
      accountId == null &&
      sourceId == null &&
      categoryId == null &&
      personId == null &&
      from == null &&
      to == null;

  TransactionFilter copyWith({
    String? search,
    Set<TransactionType>? types,
    Object? accountId = _keep,
    Object? sourceId = _keep,
    Object? categoryId = _keep,
    Object? personId = _keep,
    Object? from = _keep,
    Object? to = _keep,
  }) => TransactionFilter(
    search: search ?? this.search,
    types: types ?? this.types,
    accountId: identical(accountId, _keep)
        ? this.accountId
        : accountId as String?,
    sourceId: identical(sourceId, _keep) ? this.sourceId : sourceId as String?,
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as String?,
    personId: identical(personId, _keep) ? this.personId : personId as String?,
    from: identical(from, _keep) ? this.from : from as DateTime?,
    to: identical(to, _keep) ? this.to : to as DateTime?,
  );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.search == search &&
      other.types.length == types.length &&
      other.types.containsAll(types) &&
      other.accountId == accountId &&
      other.sourceId == sourceId &&
      other.categoryId == categoryId &&
      other.personId == personId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAllUnordered(types),
    accountId,
    sourceId,
    categoryId,
    personId,
    from,
    to,
  );
}

const Object _keep = Object();

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Checks the rules every transaction must obey. Throws [LedgerException].
  void validate(TransactionInput t) {
    if (t.amount <= 0) throw LedgerException('Amount must be above 0.');
    if (!allocationsValid(t.allocations, t.amount)) {
      throw LedgerException(
        'The source split must add up exactly to the amount.',
      );
    }
    if (t.type == TransactionType.transfer) {
      if (t.toAccountId == null) {
        throw LedgerException('Choose the account to transfer to.');
      }
      if (t.toAccountId == t.accountId) {
        throw LedgerException('Cannot transfer to the same account.');
      }
    } else if (t.toAccountId != null) {
      throw LedgerException('Only transfers have a destination account.');
    }
    if (t.type == TransactionType.expense && t.categoryId == null) {
      throw LedgerException('Choose a category.');
    }
  }

  /// Saves (inserts or updates) a transaction and its allocations in ONE
  /// database transaction. Returns the transaction id.
  Future<String> save(TransactionInput input) async {
    validate(input);
    final id = input.id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final row = TransactionsCompanion(
        id: Value(id),
        type: Value(input.type),
        amount: Value(input.amount),
        accountId: Value(input.accountId),
        toAccountId: Value(input.toAccountId),
        categoryId: Value(input.categoryId),
        personId: Value(input.personId),
        dueId: Value(input.dueId),
        subscriptionId: Value(input.subscriptionId),
        date: Value(input.date),
        note: Value(input.note),
        createdAt: Value(existing?.createdAt ?? input.createdAt ?? now),
        updatedAt: Value(now),
      );
      await _db.into(_db.transactions).insertOnConflictUpdate(row);
      await (_db.delete(
        _db.transactionAllocations,
      )..where((a) => a.transactionId.equals(id))).go();
      for (final a in input.allocations) {
        await _db
            .into(_db.transactionAllocations)
            .insert(
              TransactionAllocationsCompanion.insert(
                id: _uuid.v4(),
                transactionId: id,
                sourceId: a.sourceId,
                amount: a.amount,
              ),
            );
      }
    });
    return id;
  }

  Future<TransactionInput?> get(String id) async {
    final t = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (t == null) return null;
    final allocs = await (_db.select(
      _db.transactionAllocations,
    )..where((a) => a.transactionId.equals(id))).get();
    return TransactionInput(
      id: t.id,
      type: t.type,
      amount: t.amount,
      accountId: t.accountId,
      toAccountId: t.toAccountId,
      categoryId: t.categoryId,
      personId: t.personId,
      dueId: t.dueId,
      subscriptionId: t.subscriptionId,
      date: t.date,
      note: t.note,
      createdAt: t.createdAt,
      allocations: [
        for (final a in allocs) AllocationInput(a.sourceId, a.amount),
      ],
    );
  }

  /// Deletes a transaction and returns a snapshot (with allocations) so the
  /// caller can offer "Undo" by passing it back to [save].
  Future<TransactionInput?> delete(String id) async {
    return _db.transaction(() async {
      final snapshot = await get(id);
      if (snapshot == null) return null;
      await (_db.delete(
        _db.transactionAllocations,
      )..where((a) => a.transactionId.equals(id))).go();
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
      return snapshot;
    });
  }

  Stream<List<Transaction>> watch(TransactionFilter f) {
    final q = _db.select(_db.transactions);
    q.where((t) {
      final conds = <Expression<bool>>[];
      if (f.types.isNotEmpty) {
        conds.add(t.type.isInValues(f.types.toList()));
      }
      if (f.accountId != null) {
        conds.add(
          t.accountId.equals(f.accountId!) | t.toAccountId.equals(f.accountId!),
        );
      }
      if (f.categoryId != null) conds.add(t.categoryId.equals(f.categoryId!));
      if (f.personId != null) conds.add(t.personId.equals(f.personId!));
      if (f.from != null) conds.add(t.date.isBiggerOrEqualValue(f.from!));
      if (f.to != null) conds.add(t.date.isSmallerThanValue(f.to!));
      if (f.sourceId != null) {
        final sub = _db.selectOnly(_db.transactionAllocations)
          ..addColumns([_db.transactionAllocations.transactionId])
          ..where(_db.transactionAllocations.sourceId.equals(f.sourceId!));
        conds.add(t.id.isInQuery(sub));
      }
      final s = f.search.trim();
      if (s.isNotEmpty) {
        final like = '%${s.replaceAll('%', '')}%';
        final cats = _db.selectOnly(_db.categories)
          ..addColumns([_db.categories.id])
          ..where(_db.categories.name.like(like));
        final people = _db.selectOnly(_db.people)
          ..addColumns([_db.people.id])
          ..where(_db.people.name.like(like));
        conds.add(
          t.note.like(like) |
              t.categoryId.isInQuery(cats) |
              t.personId.isInQuery(people),
        );
      }
      return conds.isEmpty ? const Constant(true) : conds.reduce((a, b) => a & b);
    });
    q.orderBy([
      (t) => OrderingTerm.desc(t.date),
      (t) => OrderingTerm.desc(t.createdAt),
    ]);
    return q.watch();
  }

  Stream<List<TransactionAllocation>> watchAllAllocations() =>
      _db.select(_db.transactionAllocations).watch();
}
