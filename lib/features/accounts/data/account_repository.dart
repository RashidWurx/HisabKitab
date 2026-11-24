import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_models.dart';

/// Thrown when something cannot be deleted because it is in use.
/// The UI then offers to archive it or move its data elsewhere.
class BlockedDeleteException implements Exception {
  BlockedDeleteException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AccountDraft {
  const AccountDraft({
    this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    this.openingSplit = const [],
    this.defaultSpendingSourceId,
    this.status = ActiveStatus.active,
    this.includeInTotal = true,
    required this.colorValue,
    required this.iconKey,
    this.note,
    this.goalAmount,
    this.goalDate,
  });

  final String? id;
  final String name;
  final AccountType type;
  final int openingBalance;

  /// Part of the opening balance that belongs to named sources. The remainder
  /// counts as "Other money".
  final List<AllocationInput> openingSplit;
  final String? defaultSpendingSourceId;
  final ActiveStatus status;
  final bool includeInTotal;
  final int colorValue;
  final String iconKey;
  final String? note;
  final int? goalAmount;
  final DateTime? goalDate;
}

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Account>> watchAll() => (_db.select(
    _db.accounts,
  )..orderBy([(a) => OrderingTerm.asc(a.sortOrder)])).watch();

  Stream<List<AccountOpeningAllocation>> watchOpeningAllocations() =>
      _db.select(_db.accountOpeningAllocations).watch();

  Future<Account?> get(String id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<AccountOpeningAllocation>> openingSplit(String accountId) =>
      (_db.select(
        _db.accountOpeningAllocations,
      )..where((o) => o.accountId.equals(accountId))).get();

  void _validate(AccountDraft d) {
    if (d.name.trim().isEmpty) throw LedgerException('Enter a name.');
    if (d.openingBalance < 0) {
      throw LedgerException('Opening balance cannot be negative.');
    }
    var sum = 0;
    for (final s in d.openingSplit) {
      if (s.amount <= 0) throw LedgerException('Split amounts must be above 0.');
      sum += s.amount;
    }
    if (sum > d.openingBalance) {
      throw LedgerException(
        'The source split is larger than the opening balance.',
      );
    }
  }

  Future<String> save(AccountDraft d) async {
    _validate(d);
    final id = d.id ?? _uuid.v4();
    await _db.transaction(() async {
      final existing = await get(id);
      final maxOrder = await _nextSortOrder();
      await _db
          .into(_db.accounts)
          .insertOnConflictUpdate(
            AccountsCompanion(
              id: Value(id),
              name: Value(d.name.trim()),
              type: Value(d.type),
              openingBalance: Value(d.openingBalance),
              defaultSpendingSourceId: Value(d.defaultSpendingSourceId),
              status: Value(d.status),
              includeInTotal: Value(d.includeInTotal),
              colorValue: Value(d.colorValue),
              iconKey: Value(d.iconKey),
              note: Value(d.note),
              goalAmount: Value(d.goalAmount),
              goalDate: Value(d.goalDate),
              isArchived: Value(existing?.isArchived ?? false),
              sortOrder: Value(existing?.sortOrder ?? maxOrder),
              createdAt: Value(existing?.createdAt ?? DateTime.now()),
            ),
          );
      await (_db.delete(
        _db.accountOpeningAllocations,
      )..where((o) => o.accountId.equals(id))).go();
      for (final s in d.openingSplit) {
        if (s.sourceId == otherMoneySourceId) continue; // remainder = other
        await _db
            .into(_db.accountOpeningAllocations)
            .insert(
              AccountOpeningAllocationsCompanion.insert(
                accountId: id,
                sourceId: s.sourceId,
                amount: s.amount,
              ),
            );
      }
    });
    return id;
  }

  Future<int> _nextSortOrder() async {
    final max = _db.accounts.sortOrder.max();
    final row = await (_db.selectOnly(_db.accounts)..addColumns([max]))
        .getSingle();
    return (row.read(max) ?? -1) + 1;
  }

  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (var i = 0; i < idsInOrder.length; i++) {
      await (_db.update(_db.accounts)..where((a) => a.id.equals(idsInOrder[i])))
          .write(AccountsCompanion(sortOrder: Value(i)));
    }
  });

  Future<void> setArchived(String id, bool archived) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(isArchived: Value(archived)),
      );

  Future<void> setStatus(String id, ActiveStatus status) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(status: Value(status)),
      );

  /// How many transactions touch this account.
  Future<int> transactionCount(String id) async {
    final c = _db.transactions.id.count();
    final row =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([c])
              ..where(
                _db.transactions.accountId.equals(id) |
                    _db.transactions.toAccountId.equals(id),
              ))
            .getSingle();
    return row.read(c) ?? 0;
  }

  /// Deletes an account. Blocked when it has transactions (archive it or
  /// move its transactions first).
  Future<void> delete(String id) async {
    if (await transactionCount(id) > 0) {
      throw BlockedDeleteException(
        'This account has transactions. Archive it, or move its transactions to another account.',
      );
    }
    await _db.transaction(() async {
      await (_db.update(_db.incomeSources)
            ..where((s) => s.linkedAccountId.equals(id)))
          .write(const IncomeSourcesCompanion(linkedAccountId: Value(null)));
      await (_db.update(_db.categories)
            ..where((c) => c.defaultAccountId.equals(id)))
          .write(const CategoriesCompanion(defaultAccountId: Value(null)));
      await (_db.update(_db.people)
            ..where((p) => p.defaultAccountId.equals(id)))
          .write(const PeopleCompanion(defaultAccountId: Value(null)));
      await (_db.delete(
        _db.accountOpeningAllocations,
      )..where((o) => o.accountId.equals(id))).go();
      await (_db.delete(_db.accounts)..where((a) => a.id.equals(id))).go();
    });
  }

  /// Moves every transaction (and due / subscription) from one account to
  /// another, then the old account can be deleted.
  Future<void> moveTransactions(String fromId, String toId) async {
    if (fromId == toId) throw LedgerException('Choose a different account.');
    final clash =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.type.equals(TransactionType.transfer.name) &
                  ((t.accountId.equals(fromId) & t.toAccountId.equals(toId)) |
                      (t.accountId.equals(toId) & t.toAccountId.equals(fromId))),
            ))
            .get();
    if (clash.isNotEmpty) {
      throw LedgerException(
        'Some transfers go between these two accounts and would become transfers to the same account. Delete those first.',
      );
    }
    await _db.transaction(() async {
      await (_db.update(_db.transactions)
            ..where((t) => t.accountId.equals(fromId)))
          .write(TransactionsCompanion(accountId: Value(toId)));
      await (_db.update(_db.transactions)
            ..where((t) => t.toAccountId.equals(fromId)))
          .write(TransactionsCompanion(toAccountId: Value(toId)));
      await (_db.update(_db.dues)..where((d) => d.accountId.equals(fromId)))
          .write(DuesCompanion(accountId: Value(toId)));
      await (_db.update(_db.subscriptions)
            ..where((s) => s.accountId.equals(fromId)))
          .write(SubscriptionsCompanion(accountId: Value(toId)));
    });
  }
}
