import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';

class SourceDraft {
  const SourceDraft({
    this.id,
    required this.name,
    this.type = SourceType.job,
    this.linkedAccountId,
    this.expectedAmount,
    this.payScheduleType,
    this.payDay,
    this.payIntervalDays,
    this.payAnchorDate,
    this.status = ActiveStatus.active,
    required this.colorValue,
    required this.iconKey,
    this.note,
  });

  final String? id;
  final String name;
  final SourceType type;
  final String? linkedAccountId;
  final int? expectedAmount;
  final PayScheduleType? payScheduleType;
  final int? payDay;
  final int? payIntervalDays;
  final DateTime? payAnchorDate;
  final ActiveStatus status;
  final int colorValue;
  final String iconKey;
  final String? note;
}

class SourceRepository {
  SourceRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<IncomeSource>> watchAll() => (_db.select(
    _db.incomeSources,
  )..orderBy([(s) => OrderingTerm.asc(s.sortOrder)])).watch();

  Future<IncomeSource?> get(String id) => (_db.select(
    _db.incomeSources,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<String> save(SourceDraft d) async {
    if (d.name.trim().isEmpty) throw LedgerException('Enter a name.');
    final id = d.id ?? _uuid.v4();
    if (id == otherMoneySourceId) {
      // The built-in source can only change colour/icon/note.
      await (_db.update(_db.incomeSources)..where((s) => s.id.equals(id)))
          .write(
            IncomeSourcesCompanion(
              colorValue: Value(d.colorValue),
              iconKey: Value(d.iconKey),
              note: Value(d.note),
            ),
          );
      return id;
    }
    await _db.transaction(() async {
      final existing = await get(id);
      final max = _db.incomeSources.sortOrder.max();
      final row = await (_db.selectOnly(_db.incomeSources)..addColumns([max]))
          .getSingle();
      await _db
          .into(_db.incomeSources)
          .insertOnConflictUpdate(
            IncomeSourcesCompanion(
              id: Value(id),
              name: Value(d.name.trim()),
              type: Value(d.type),
              linkedAccountId: Value(d.linkedAccountId),
              expectedAmount: Value(d.expectedAmount),
              payScheduleType: Value(d.payScheduleType),
              payDay: Value(d.payDay),
              payIntervalDays: Value(d.payIntervalDays),
              payAnchorDate: Value(d.payAnchorDate),
              status: Value(d.status),
              colorValue: Value(d.colorValue),
              iconKey: Value(d.iconKey),
              note: Value(d.note),
              isArchived: Value(existing?.isArchived ?? false),
              sortOrder: Value(existing?.sortOrder ?? (row.read(max) ?? 0) + 1),
              createdAt: Value(existing?.createdAt ?? DateTime.now()),
            ),
          );
    });
    return id;
  }

  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    for (var i = 0; i < idsInOrder.length; i++) {
      await (_db.update(
        _db.incomeSources,
      )..where((s) => s.id.equals(idsInOrder[i]))).write(
        IncomeSourcesCompanion(sortOrder: Value(i)),
      );
    }
  });

  Future<void> setArchived(String id, bool archived) async {
    if (id == otherMoneySourceId) {
      throw LedgerException('"Other money" cannot be archived.');
    }
    await (_db.update(_db.incomeSources)..where((s) => s.id.equals(id))).write(
      IncomeSourcesCompanion(isArchived: Value(archived)),
    );
  }

  Future<void> setStatus(String id, ActiveStatus status) async {
    if (id == otherMoneySourceId) {
      throw LedgerException('"Other money" is always active.');
    }
    await (_db.update(_db.incomeSources)..where((s) => s.id.equals(id))).write(
      IncomeSourcesCompanion(status: Value(status)),
    );
  }

  /// Number of transaction allocations and opening splits tagged to a source.
  Future<int> usageCount(String id) async {
    final c = _db.transactionAllocations.id.count();
    final a =
        await (_db.selectOnly(_db.transactionAllocations)
              ..addColumns([c])
              ..where(_db.transactionAllocations.sourceId.equals(id)))
            .getSingle();
    final c2 = _db.accountOpeningAllocations.accountId.count();
    final o =
        await (_db.selectOnly(_db.accountOpeningAllocations)
              ..addColumns([c2])
              ..where(_db.accountOpeningAllocations.sourceId.equals(id)))
            .getSingle();
    return (a.read(c) ?? 0) + (o.read(c2) ?? 0);
  }

  /// Deletes a source. Blocked for "Other money" and for sources with money
  /// tagged to them (archive it or move its allocations first).
  Future<void> delete(String id) async {
    if (id == otherMoneySourceId) {
      throw BlockedDeleteException('"Other money" cannot be deleted.');
    }
    if (await usageCount(id) > 0) {
      throw BlockedDeleteException(
        'This source has money tagged to it. Archive it, or move its money to another source.',
      );
    }
    await _db.transaction(() async {
      await (_db.update(_db.accounts)
            ..where((a) => a.defaultSpendingSourceId.equals(id)))
          .write(
            const AccountsCompanion(defaultSpendingSourceId: Value(null)),
          );
      await (_db.update(_db.categories)
            ..where((c) => c.defaultSourceId.equals(id)))
          .write(const CategoriesCompanion(defaultSourceId: Value(null)));
      await (_db.update(_db.dues)..where((d) => d.sourceId.equals(id))).write(
        const DuesCompanion(sourceId: Value(null)),
      );
      await (_db.delete(_db.incomeSources)..where((s) => s.id.equals(id))).go();
    });
  }

  /// Re-tags all of [fromId]'s money (transactions, opening splits, defaults)
  /// to [toId] (which may be "Other money"). Then [fromId] can be deleted.
  Future<void> moveAllocations(String fromId, String toId) async {
    if (fromId == toId) throw LedgerException('Choose a different source.');
    if (fromId == otherMoneySourceId) {
      throw LedgerException('"Other money" cannot be moved.');
    }
    await _db.transaction(() async {
      await (_db.update(
        _db.transactionAllocations,
      )..where((a) => a.sourceId.equals(fromId))).write(
        TransactionAllocationsCompanion(sourceId: Value(toId)),
      );
      // Opening splits: merge into an existing row for the same account.
      final opens = await (_db.select(
        _db.accountOpeningAllocations,
      )..where((o) => o.sourceId.equals(fromId))).get();
      for (final o in opens) {
        await (_db.delete(_db.accountOpeningAllocations)..where(
              (x) => x.accountId.equals(o.accountId) & x.sourceId.equals(fromId),
            ))
            .go();
        if (toId == otherMoneySourceId) continue; // remainder is "Other money"
        final target =
            await (_db.select(_db.accountOpeningAllocations)..where(
                  (x) => x.accountId.equals(o.accountId) & x.sourceId.equals(toId),
                ))
                .getSingleOrNull();
        await _db
            .into(_db.accountOpeningAllocations)
            .insertOnConflictUpdate(
              AccountOpeningAllocationsCompanion.insert(
                accountId: o.accountId,
                sourceId: toId,
                amount: o.amount + (target?.amount ?? 0),
              ),
            );
      }
      await (_db.update(_db.accounts)
            ..where((a) => a.defaultSpendingSourceId.equals(fromId)))
          .write(AccountsCompanion(defaultSpendingSourceId: Value(toId)));
      await (_db.update(_db.categories)
            ..where((c) => c.defaultSourceId.equals(fromId)))
          .write(CategoriesCompanion(defaultSourceId: Value(toId)));
      await (_db.update(_db.dues)..where((d) => d.sourceId.equals(fromId)))
          .write(DuesCompanion(sourceId: Value(toId)));
    });
  }
}
