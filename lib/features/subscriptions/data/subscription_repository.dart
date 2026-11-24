import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/allocation_logic.dart';
import '../../transactions/domain/transaction_models.dart';
import '../domain/subscription_logic.dart';

class SubscriptionDraft {
  const SubscriptionDraft({
    this.id,
    required this.name,
    required this.amount,
    required this.billingUnit,
    this.billingEvery = 1,
    required this.nextDueDate,
    required this.accountId,
    this.categoryId,
    this.reminderDaysBefore,
    this.status = SubscriptionStatus.active,
    this.note,
  });

  final String? id;
  final String name;
  final int amount;
  final BillingUnit billingUnit;
  final int billingEvery;
  final DateTime nextDueDate;
  final String accountId;
  final String? categoryId;
  final int? reminderDaysBefore;
  final SubscriptionStatus status;
  final String? note;
}

/// Spent on subscriptions: this month / this year / all time.
class SubscriptionSpend {
  const SubscriptionSpend({
    required this.thisMonth,
    required this.thisYear,
    required this.allTime,
  });

  final int thisMonth;
  final int thisYear;
  final int allTime;

  static const zero = SubscriptionSpend(thisMonth: 0, thisYear: 0, allTime: 0);
}

class SubscriptionRepository {
  SubscriptionRepository(this._db) : _txs = TransactionRepository(_db);

  final AppDatabase _db;
  final TransactionRepository _txs;
  static const _uuid = Uuid();

  Stream<List<Subscription>> watchAll() => (_db.select(
    _db.subscriptions,
  )..orderBy([(s) => OrderingTerm.asc(s.nextDueDate)])).watch();

  Future<Subscription?> get(String id) => (_db.select(
    _db.subscriptions,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<String> save(SubscriptionDraft d) async {
    if (d.name.trim().isEmpty) throw LedgerException('Enter a name.');
    if (d.amount <= 0) throw LedgerException('Amount must be above 0.');
    if (d.billingEvery < 1) throw LedgerException('Billing cycle must be at least 1.');
    final id = d.id ?? _uuid.v4();
    final existing = await get(id);
    final due = DateTime(
      d.nextDueDate.year,
      d.nextDueDate.month,
      d.nextDueDate.day,
    );
    await _db
        .into(_db.subscriptions)
        .insertOnConflictUpdate(
          SubscriptionsCompanion(
            id: Value(id),
            name: Value(d.name.trim()),
            amount: Value(d.amount),
            billingUnit: Value(d.billingUnit),
            billingEvery: Value(d.billingEvery),
            nextDueDate: Value(due),
            anchorDay: Value(
              // Keep the original billing day unless the date was edited.
              existing != null && existing.nextDueDate == due
                  ? existing.anchorDay
                  : due.day,
            ),
            accountId: Value(d.accountId),
            categoryId: Value(d.categoryId),
            reminderDaysBefore: Value(d.reminderDaysBefore),
            status: Value(d.status),
            note: Value(
              (d.note == null || d.note!.trim().isEmpty) ? null : d.note!.trim(),
            ),
            createdAt: Value(existing?.createdAt ?? DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> setStatus(String id, SubscriptionStatus status) =>
      (_db.update(_db.subscriptions)..where((s) => s.id.equals(id))).write(
        SubscriptionsCompanion(status: Value(status)),
      );

  /// Deleting keeps the expenses already recorded (they just lose the link).
  Future<void> delete(String id) => _db.transaction(() async {
    await (_db.update(_db.transactions)
          ..where((t) => t.subscriptionId.equals(id)))
        .write(const TransactionsCompanion(subscriptionId: Value(null)));
    await (_db.delete(_db.subscriptions)..where((s) => s.id.equals(id))).go();
  });

  Future<String?> _defaultCategory(Subscription s) async {
    if (s.categoryId != null) return s.categoryId;
    final byName =
        await (_db.select(_db.categories)..where(
              (c) =>
                  c.name.equals('Subscriptions') &
                  c.kind.equals(CategoryKind.expense.name),
            ))
            .getSingleOrNull();
    if (byName != null) return byName.id;
    final any =
        await (_db.select(_db.categories)
              ..where((c) => c.kind.equals(CategoryKind.expense.name))
              ..limit(1))
            .getSingleOrNull();
    return any?.id;
  }

  /// "Mark paid": records an expense linked to the subscription (from its
  /// account) and moves the next due date forward by one cycle. The amount
  /// can differ from the usual one.
  Future<String> markPaid(
    String id, {
    int? amount,
    DateTime? date,
    List<AllocationInput>? allocations,
  }) async {
    final s = await get(id);
    if (s == null) throw LedgerException('Subscription not found.');
    final paid = amount ?? s.amount;
    if (paid <= 0) throw LedgerException('Amount must be above 0.');
    final categoryId = await _defaultCategory(s);
    if (categoryId == null) throw LedgerException('Add an expense category first.');
    final category = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(s.accountId))).getSingleOrNull();
    final alloc =
        allocations ??
        [
          AllocationInput(
            autoPickSource(
              balancesInAccount: LedgerService.sourcesInAccount(
                await LedgerService(_db).sourceBalances(),
                s.accountId,
              ),
              categoryDefaultSourceId: category?.defaultSourceId,
              accountDefaultSourceId: account?.defaultSpendingSourceId,
              fallbackSourceId: otherMoneySourceId,
            ),
            paid,
          ),
        ];
    late String txId;
    await _db.transaction(() async {
      txId = await _txs.save(
        TransactionInput(
          type: TransactionType.expense,
          amount: paid,
          accountId: s.accountId,
          categoryId: categoryId,
          subscriptionId: s.id,
          date: date ?? DateTime.now(),
          note: s.name,
          allocations: alloc,
        ),
      );
      await (_db.update(_db.subscriptions)..where((x) => x.id.equals(id)))
          .write(
            SubscriptionsCompanion(
              nextDueDate: Value(
                nextBillingDate(
                  from: s.nextDueDate,
                  unit: s.billingUnit,
                  every: s.billingEvery,
                  anchorDay: s.anchorDay,
                ),
              ),
            ),
          );
    });
    return txId;
  }

  /// Payment history of one subscription, newest first.
  Stream<List<Transaction>> watchPayments(String id) =>
      (_db.select(_db.transactions)
            ..where((t) => t.subscriptionId.equals(id))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  /// Totals spent on subscriptions (all of them, or one).
  /// [monthStart] is the start of the current month-period (respects the
  /// month start day setting); defaults to the 1st of this month.
  Stream<SubscriptionSpend> watchSpend({
    String? subscriptionId,
    DateTime? monthStart,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final monthFrom = monthStart ?? DateTime(today.year, today.month, 1);
    final yearStart = DateTime(today.year, 1, 1);
    return _db
        .customSelect(
          '''
SELECT
  COALESCE(SUM(CASE WHEN t.date >= ? THEN t.amount END), 0) AS month_total,
  COALESCE(SUM(CASE WHEN t.date >= ? THEN t.amount END), 0) AS year_total,
  COALESCE(SUM(t.amount), 0) AS all_total
  FROM transactions t
 WHERE t.subscription_id IS NOT NULL
   ${subscriptionId == null ? '' : 'AND t.subscription_id = ?'}
''',
          variables: [
            Variable.withDateTime(monthFrom),
            Variable.withDateTime(yearStart),
            if (subscriptionId != null) Variable(subscriptionId),
          ],
          readsFrom: {_db.transactions},
        )
        .watchSingle()
        .map(
          (r) => SubscriptionSpend(
            thisMonth: r.read<int>('month_total'),
            thisYear: r.read<int>('year_total'),
            allTime: r.read<int>('all_total'),
          ),
        );
  }
}
