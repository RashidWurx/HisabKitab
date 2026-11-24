import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/home/data/dashboard_service.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

void main() {
  late AppDatabase db;
  late TransactionRepository txs;
  late DashboardService dash;
  late String meezan, job1;
  final now = DateTime(2026, 11, 25, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    txs = TransactionRepository(db);
    dash = DashboardService(db);
    job1 = await SourceRepository(db).save(
      const SourceDraft(name: 'Job 1', colorValue: 1, iconKey: 'work'),
    );
    meezan = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Meezan',
        type: AccountType.bank,
        openingBalance: 0,
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> addDue(
    String id,
    DueKind kind,
    int total,
    DateTime due, {
    String? sourceId,
  }) => db
      .into(db.dues)
      .insert(
        DuesCompanion.insert(
          id: id,
          title: id,
          kind: kind,
          totalAmount: total,
          accountId: meezan,
          originalDueDate: due,
          currentDueDate: due,
          createdAt: now,
          sourceId: Value(sourceId),
        ),
      );

  TransactionInput payment(
    String dueId,
    TransactionType type,
    int amount,
  ) => TransactionInput(
    type: type,
    amount: amount,
    accountId: meezan,
    dueId: dueId,
    date: now,
    allocations: [AllocationInput(job1, amount)],
  );

  test('due summary: partial payments, overdue count, cancelled ignored',
      () async {
    await addDue('web', DueKind.expectedIncome, 20000 * rs,
        DateTime(2026, 11, 20),
        sourceId: job1);
    await txs.save(payment('web', TransactionType.income, 10000 * rs));
    await addDue('ali', DueKind.lent, 5000 * rs, DateTime(2026, 12, 5));
    // The lend_out that created the due is NOT a payment.
    await txs.save(payment('ali', TransactionType.lendOut, 5000 * rs));
    await addDue('sara', DueKind.borrowed, 3000 * rs, DateTime(2026, 12, 1));
    await txs.save(payment('sara', TransactionType.repayOut, 1000 * rs));
    await addDue('gone', DueKind.expectedIncome, 999 * rs,
        DateTime(2026, 11, 1));
    await (db.update(db.dues)..where((d) => d.id.equals('gone'))).write(
      DuesCompanion(cancelledAt: Value(now)),
    );

    final s = await dash.watchDueSummary(now: now).first;
    expect(s.toReceive, (10000 + 5000) * rs);
    expect(s.toPay, 2000 * rs);
    expect(s.overdueCount, 1); // only "web" is past due
  });

  test('settled due drops out of the summary', () async {
    await addDue('a', DueKind.expectedIncome, 100 * rs, DateTime(2026, 12, 1));
    await txs.save(payment('a', TransactionType.income, 100 * rs));
    final s = await dash.watchDueSummary(now: now).first;
    expect(s.toReceive, 0);
  });

  test('source and account rows (period flows + expected)', () async {
    await txs.save(
      TransactionInput(
        type: TransactionType.income,
        amount: 80000 * rs,
        accountId: meezan,
        date: DateTime(2026, 11, 10),
        allocations: [AllocationInput(job1, 80000 * rs)],
      ),
    );
    await txs.save(
      TransactionInput(
        type: TransactionType.expense,
        amount: 52000 * rs,
        accountId: meezan,
        categoryId: 'cat_exp_rent',
        date: DateTime(2026, 11, 12),
        allocations: [AllocationInput(job1, 52000 * rs)],
      ),
    );
    await addDue('pay', DueKind.expectedIncome, 25000 * rs,
        DateTime(2026, 12, 1),
        sourceId: job1);
    final range = DateRange(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 12, 1),
    );
    final src = (await dash.watchSourceRows(range).first)[job1]!;
    expect(src.received, 80000 * rs);
    expect(src.spent, 52000 * rs);
    expect(src.expected, 25000 * rs);
    expect(src.expectedAccountId, meezan);

    final acc = (await dash.watchAccountRows(range).first)[meezan]!;
    expect(acc.moneyIn, 80000 * rs);
    expect(acc.moneyOut, 52000 * rs);
    expect(acc.expected, 25000 * rs);

    // Outside the period nothing counts as flow.
    final other = await dash
        .watchSourceRows(
          DateRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 11, 1)),
        )
        .first;
    expect(other[job1]?.received ?? 0, 0);
  });

  test('upcoming: dues, subscriptions and reminders in the next 7 days',
      () async {
    await addDue('soon', DueKind.expectedIncome, 25000 * rs,
        DateTime(2026, 11, 26));
    await addDue('later', DueKind.expectedIncome, 1 * rs,
        DateTime(2026, 12, 20));
    await db
        .into(db.subscriptions)
        .insert(
          SubscriptionsCompanion.insert(
            id: 'spotify',
            name: 'Spotify',
            amount: 1100 * rs,
            billingUnit: BillingUnit.month,
            nextDueDate: DateTime(2026, 11, 28),
            accountId: meezan,
            createdAt: now,
          ),
        );
    await db
        .into(db.customReminders)
        .insert(
          CustomRemindersCompanion.insert(
            id: 'rent',
            title: 'Pay rent',
            remindAt: DateTime(2026, 11, 30, 9),
            createdAt: now,
          ),
        );
    final items = await dash.watchUpcoming(now: now).first;
    expect(items.map((i) => i.title), ['soon', 'Spotify', 'Pay rent']);
    expect(items.first.isMoneyIn, isTrue);
    expect(items[1].isMoneyIn, isFalse);
    expect(items[1].amount, 1100 * rs);
  });

  test('top categories fold the rest into one slice', () {
    const spend = [
      CategorySpend('a', 500),
      CategorySpend('b', 400),
      CategorySpend('c', 300),
      CategorySpend('d', 200),
    ];
    final top = DashboardService.topWithOther(spend, 2);
    expect(top.length, 3);
    expect(top.last.categoryId, DashboardService.otherCategoriesId);
    expect(top.last.amount, 500);
    expect(DashboardService.topWithOther(spend, 4), spend);
  });

  test('totals per range (last months bar chart)', () async {
    Future<void> add(TransactionType type, DateTime d, int amount) => txs.save(
      TransactionInput(
        type: type,
        amount: amount * rs,
        accountId: meezan,
        categoryId: type == TransactionType.expense ? 'cat_exp_rent' : null,
        date: d,
        allocations: [AllocationInput(job1, amount * rs)],
      ),
    );
    await add(TransactionType.income, DateTime(2026, 10, 5), 1000);
    await add(TransactionType.expense, DateTime(2026, 10, 6), 400);
    await add(TransactionType.income, DateTime(2026, 11, 5), 2000);
    final ranges = [
      DateRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 11, 1)),
      DateRange(start: DateTime(2026, 11, 1), end: DateTime(2026, 12, 1)),
    ];
    final r = await dash.watchTotalsPerRange(ranges).first;
    expect(r[0].moneyIn, 1000 * rs);
    expect(r[0].moneyOut, 400 * rs);
    expect(r[1].moneyIn, 2000 * rs);
    expect(r[1].moneyOut, 0);
  });
}
