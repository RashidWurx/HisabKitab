import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/database/seed.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/allocation_logic.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100; // 1 rupee in paisa

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late SourceRepository sources;
  late TransactionRepository txs;
  late LedgerService ledger;
  late String meezan, jazz, job1, freelance;
  final day = DateTime(2026, 11, 24);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    sources = SourceRepository(db);
    txs = TransactionRepository(db);
    ledger = LedgerService(db);
    job1 = await sources.save(
      const SourceDraft(name: 'Job 1', colorValue: 1, iconKey: 'work'),
    );
    freelance = await sources.save(
      const SourceDraft(name: 'Freelance', colorValue: 1, iconKey: 'laptop'),
    );
    meezan = await accounts.save(
      AccountDraft(
        name: 'Meezan',
        type: AccountType.bank,
        openingBalance: 5000 * rs,
        openingSplit: [AllocationInput(job1, 3000 * rs)],
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
    jazz = await accounts.save(
      const AccountDraft(
        name: 'JazzCash',
        type: AccountType.mobileWallet,
        openingBalance: 0,
        colorValue: 1,
        iconKey: 'phone',
      ),
    );
  });

  tearDown(() => db.close());

  TransactionInput income(int amount, String source, {String? account}) =>
      TransactionInput(
        type: TransactionType.income,
        amount: amount,
        accountId: account ?? meezan,
        date: day,
        allocations: [AllocationInput(source, amount)],
      );

  TransactionInput expense(int amount, List<AllocationInput> split) =>
      TransactionInput(
        type: TransactionType.expense,
        amount: amount,
        accountId: meezan,
        categoryId: 'cat_exp_rent',
        date: day,
        allocations: split,
      );

  Future<void> expectConsistent() async {
    final bySource = LedgerService.accountTotals(await ledger.sourceBalances());
    final independent = await ledger.accountBalancesFromTransactions();
    for (final id in independent.keys) {
      expect(bySource[id] ?? 0, independent[id], reason: 'account $id');
    }
  }

  test('opening balance splits across sources; remainder is Other money', () async {
    final b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, job1)], 3000 * rs);
    expect(b[AccountSource(meezan, otherMoneySourceId)], 2000 * rs);
    await expectConsistent();
  });

  test('income, split expense and transfer keep sources and accounts in sync',
      () async {
    await txs.save(income(40000 * rs, freelance));
    await txs.save(
      expense(10000 * rs, [
        AllocationInput(job1, 3000 * rs),
        AllocationInput(freelance, 7000 * rs),
      ]),
    );
    // Move 5,000 of freelance money Meezan -> JazzCash: source goes with it.
    await txs.save(
      TransactionInput(
        type: TransactionType.transfer,
        amount: 5000 * rs,
        accountId: meezan,
        toAccountId: jazz,
        date: day,
        allocations: [AllocationInput(freelance, 5000 * rs)],
      ),
    );
    final b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, freelance)], (40000 - 7000 - 5000) * rs);
    expect(b[AccountSource(jazz, freelance)], 5000 * rs);
    expect(b[AccountSource(meezan, job1)], isNull); // 3,000 in, 3,000 out
    final accts = LedgerService.accountTotals(b);
    expect(accts[meezan], (5000 + 40000 - 10000 - 5000) * rs);
    expect(accts[jazz], 5000 * rs);
    final totals = LedgerService.sourceTotals(b);
    expect(totals[freelance], 33000 * rs);
    await expectConsistent();
  });

  test('lend/borrow/repay change balances but are not income or expense',
      () async {
    await txs.save(
      TransactionInput(
        type: TransactionType.lendOut,
        amount: 1000 * rs,
        accountId: meezan,
        date: day,
        allocations: [AllocationInput(job1, 1000 * rs)],
      ),
    );
    await txs.save(
      TransactionInput(
        type: TransactionType.repayIn,
        amount: 400 * rs,
        accountId: meezan,
        date: day,
        allocations: [AllocationInput(job1, 400 * rs)],
      ),
    );
    final b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, job1)], (3000 - 1000 + 400) * rs);
    final stats = await ledger.watchPeriodTotals(DateRange.all).first;
    expect(stats.moneyIn, 0);
    expect(stats.moneyOut, 0);
    await expectConsistent();
  });

  test('edit and delete keep everything consistent; undo restores', () async {
    final id = await txs.save(income(1000 * rs, freelance));
    final input = (await txs.get(id))!;
    await txs.save(
      input.copyWith(
        amount: 1500 * rs,
        allocations: [AllocationInput(freelance, 1500 * rs)],
      ),
    );
    var b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, freelance)], 1500 * rs);
    await expectConsistent();

    final snapshot = await txs.delete(id);
    b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, freelance)], isNull);
    await expectConsistent();

    await txs.save(snapshot!); // undo
    b = await ledger.sourceBalances();
    expect(b[AccountSource(meezan, freelance)], 1500 * rs);
    await expectConsistent();
  });

  test('validation: amount, split sum, same-account transfer', () async {
    expect(
      () => txs.save(income(0, job1)),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => txs.save(
        expense(100 * rs, [AllocationInput(job1, 60 * rs)]), // sums to 60
      ),
      throwsA(isA<LedgerException>()),
    );
    expect(
      () => txs.save(
        TransactionInput(
          type: TransactionType.transfer,
          amount: 100 * rs,
          accountId: meezan,
          toAccountId: meezan,
          date: day,
          allocations: [AllocationInput(job1, 100 * rs)],
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test('a failed save leaves nothing behind (one DB transaction)', () async {
    try {
      await txs.save(
        TransactionInput(
          type: TransactionType.income,
          amount: 100 * rs,
          accountId: meezan,
          date: day,
          allocations: const [AllocationInput('no-such-source', 100 * rs)],
        ),
      );
    } catch (_) {}
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.transactionAllocations).get(), isEmpty);
  });

  test('opening split larger than opening balance is rejected', () {
    expect(
      () => accounts.save(
        AccountDraft(
          name: 'Bad',
          type: AccountType.bank,
          openingBalance: 100 * rs,
          openingSplit: [AllocationInput(job1, 200 * rs)],
          colorValue: 1,
          iconKey: 'bank',
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test('period stats: income / expense / by category / by source', () async {
    await txs.save(income(40000 * rs, freelance));
    await txs.save(
      expense(10000 * rs, [
        AllocationInput(job1, 3000 * rs),
        AllocationInput(freelance, 7000 * rs),
      ]),
    );
    final totals = await ledger.watchPeriodTotals(DateRange.all).first;
    expect(totals.moneyIn, 40000 * rs);
    expect(totals.moneyOut, 10000 * rs);
    expect(totals.net, 30000 * rs);
    expect(totals.marginPercent, 75);

    final cats = await ledger.watchSpendingByCategory(DateRange.all).first;
    expect(cats.single.categoryId, 'cat_exp_rent');
    expect(cats.single.amount, 10000 * rs);

    final fl = await ledger.watchSourceStats(freelance, DateRange.all).first;
    expect(fl.received, 40000 * rs);
    expect(fl.spent, 7000 * rs);
    final byFl = await ledger
        .watchSpendingByCategory(DateRange.all, sourceId: freelance)
        .first;
    expect(byFl.single.amount, 7000 * rs);
  });

  test('balance streams refresh when transactions change', () async {
    final seen = <int>[];
    final sub = ledger.watchAccountBalances().listen(
      (m) => seen.add(m[meezan] ?? -1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await txs.save(income(100 * rs, job1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen.first, 5000 * rs);
    expect(seen.last, 5100 * rs);
  });

  group('delete rules', () {
    test('account with transactions is blocked; move then delete works',
        () async {
      await txs.save(income(100 * rs, job1));
      expect(
        () => accounts.delete(meezan),
        throwsA(isA<BlockedDeleteException>()),
      );
      await accounts.moveTransactions(meezan, jazz);
      await accounts.delete(meezan);
      expect(await accounts.get(meezan), isNull);
      final b = LedgerService.accountTotals(await ledger.sourceBalances());
      expect(b[jazz], 100 * rs);
    });

    test('source with money is blocked; move to Other money then delete',
        () async {
      await txs.save(income(100 * rs, freelance));
      expect(
        () => sources.delete(freelance),
        throwsA(isA<BlockedDeleteException>()),
      );
      await sources.moveAllocations(freelance, otherMoneySourceId);
      await sources.delete(freelance);
      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, otherMoneySourceId)], 2100 * rs);
      await expectConsistent();
    });

    test('"Other money" can never be deleted or archived', () async {
      expect(
        () => sources.delete(otherMoneySourceId),
        throwsA(isA<BlockedDeleteException>()),
      );
      expect(
        () => sources.setArchived(otherMoneySourceId, true),
        throwsA(isA<LedgerException>()),
      );
    });
  });

  group('auto-pick and split', () {
    test('category default wins when it has money', () {
      expect(
        autoPickSource(
          balancesInAccount: {'a': 100, 'b': 500},
          categoryDefaultSourceId: 'a',
          accountDefaultSourceId: 'b',
          fallbackSourceId: 'other',
        ),
        'a',
      );
    });
    test('category default without money falls to account default', () {
      expect(
        autoPickSource(
          balancesInAccount: {'a': 0, 'b': 500},
          categoryDefaultSourceId: 'a',
          accountDefaultSourceId: 'c',
          fallbackSourceId: 'other',
        ),
        'c',
      );
    });
    test('then the source with most money, then Other money', () {
      expect(
        autoPickSource(
          balancesInAccount: {'a': 100, 'b': 500},
          fallbackSourceId: 'other',
        ),
        'b',
      );
      expect(
        autoPickSource(balancesInAccount: {}, fallbackSourceId: 'other'),
        'other',
      );
    });
    test('shortfall', () {
      expect(shortfall(sourceBalance: 300, amount: 1000), 700);
      expect(shortfall(sourceBalance: 1000, amount: 1000), 0);
      expect(shortfall(sourceBalance: -50, amount: 100), 100);
    });
    test('split fills the rest from the next biggest sources', () {
      final r = splitWithOtherSources(
        primary: 'a',
        amount: 1000,
        balancesInAccount: {'a': 300, 'b': 500, 'c': 400},
      );
      expect(r, [
        const AllocationInput('a', 300),
        const AllocationInput('b', 500),
        const AllocationInput('c', 200),
      ]);
      expect(allocationsValid(r, 1000), isTrue);
    });
    test('split leftover stays on primary when account lacks money', () {
      final r = splitWithOtherSources(
        primary: 'a',
        amount: 1000,
        balancesInAccount: {'a': 100, 'b': 200},
      );
      expect(r, [
        const AllocationInput('a', 800),
        const AllocationInput('b', 200),
      ]);
      expect(allocationsValid(r, 1000), isTrue);
    });
  });
}
