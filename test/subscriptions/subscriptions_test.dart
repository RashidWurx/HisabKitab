import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/reminders/data/reminder_repository.dart';
import 'package:hisaab/features/savings/domain/savings_logic.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/subscriptions/data/subscription_repository.dart';
import 'package:hisaab/features/subscriptions/domain/subscription_logic.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

void main() {
  group('next billing date', () {
    DateTime next(
      DateTime from,
      BillingUnit unit, [
      int every = 1,
      int? anchor,
    ]) => nextBillingDate(from: from, unit: unit, every: every, anchorDay: anchor);

    test('days and weeks', () {
      expect(next(DateTime(2026, 11, 25), BillingUnit.day, 10), DateTime(2026, 12, 5));
      expect(next(DateTime(2026, 11, 25), BillingUnit.week), DateTime(2026, 12, 2));
      expect(next(DateTime(2026, 12, 28), BillingUnit.week, 2), DateTime(2027, 1, 11));
    });

    test('monthly rolls the year and keeps the billing day', () {
      expect(next(DateTime(2026, 12, 25), BillingUnit.month), DateTime(2027, 1, 25));
      expect(next(DateTime(2026, 11, 25), BillingUnit.month, 3), DateTime(2027, 2, 25));
    });

    test('the 31st clamps in short months but returns to the 31st', () {
      final feb = next(DateTime(2027, 1, 31), BillingUnit.month, 1, 31);
      expect(feb, DateTime(2027, 2, 28));
      final mar = next(feb, BillingUnit.month, 1, 31);
      expect(mar, DateTime(2027, 3, 31));
      expect(next(DateTime(2028, 1, 31), BillingUnit.month, 1, 31), DateTime(2028, 2, 29));
    });

    test('yearly, including 29 Feb', () {
      expect(next(DateTime(2026, 12, 12), BillingUnit.year), DateTime(2027, 12, 12));
      expect(next(DateTime(2028, 2, 29), BillingUnit.year, 1, 29), DateTime(2029, 2, 28));
    });
  });

  group('monthly cost', () {
    test('month, year, week, day', () {
      expect(monthlyCost(amount: 110000, unit: BillingUnit.month, every: 1), 110000);
      expect(monthlyCost(amount: 600000, unit: BillingUnit.year, every: 1), 50000);
      expect(monthlyCost(amount: 300000, unit: BillingUnit.month, every: 3), 100000);
      expect(monthlyCost(amount: 100000, unit: BillingUnit.week, every: 1), 433333);
      expect(monthlyCost(amount: 10000, unit: BillingUnit.day, every: 1), 304167);
    });
  });

  group('subscriptions with the ledger', () {
    late AppDatabase db;
    late SubscriptionRepository subs;
    late TransactionRepository txs;
    late LedgerService ledger;
    late String meezan, job1;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      subs = SubscriptionRepository(db);
      txs = TransactionRepository(db);
      ledger = LedgerService(db);
      job1 = await SourceRepository(db).save(
        const SourceDraft(name: 'Job 1', colorValue: 1, iconKey: 'work'),
      );
      meezan = await AccountRepository(db).save(
        AccountDraft(
          name: 'Meezan',
          type: AccountType.bank,
          openingBalance: 10000 * rs,
          openingSplit: [AllocationInput(job1, 10000 * rs)],
          colorValue: 1,
          iconKey: 'bank',
        ),
      );
    });

    tearDown(() => db.close());

    Future<String> spotify({DateTime? due}) => subs.save(
      SubscriptionDraft(
        name: 'Spotify',
        amount: 1100 * rs,
        billingUnit: BillingUnit.month,
        nextDueDate: due ?? DateTime(2026, 12, 25),
        accountId: meezan,
      ),
    );

    test('mark paid creates a linked expense and moves the date forward',
        () async {
      final id = await spotify();
      await subs.markPaid(id, date: DateTime(2026, 12, 25));
      final s = (await subs.get(id))!;
      expect(s.nextDueDate, DateTime(2027, 1, 25));
      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], (10000 - 1100) * rs);
      final payments = await subs.watchPayments(id).first;
      expect(payments.single.type, TransactionType.expense);
      expect(payments.single.subscriptionId, id);
      expect(payments.single.categoryId, 'cat_exp_subscriptions');
    });

    test('amount is editable when marking paid', () async {
      final id = await spotify();
      await subs.markPaid(id, amount: 1500 * rs);
      final spend = await subs.watchSpend(subscriptionId: id).first;
      expect(spend.allTime, 1500 * rs);
    });

    test('spend totals: month, year, all time', () async {
      final id = await spotify();
      await subs.markPaid(id, date: DateTime(2026, 11, 5));
      await subs.markPaid(id, date: DateTime(2026, 3, 5));
      await subs.markPaid(id, date: DateTime(2025, 6, 5));
      final spend = await subs
          .watchSpend(now: DateTime(2026, 11, 25))
          .first;
      expect(spend.thisMonth, 1100 * rs);
      expect(spend.thisYear, 2200 * rs);
      expect(spend.allTime, 3300 * rs);
    });

    test('monthly total counts only active subscriptions', () async {
      await spotify();
      final yearly = await subs.save(
        SubscriptionDraft(
          name: 'Cloud',
          amount: 6000 * rs,
          billingUnit: BillingUnit.year,
          nextDueDate: DateTime(2026, 12, 12),
          accountId: meezan,
        ),
      );
      var all = await subs.watchAll().first;
      expect(totalMonthlyCost(all), (1100 + 500) * rs);
      await subs.setStatus(yearly, SubscriptionStatus.paused);
      all = await subs.watchAll().first;
      expect(totalMonthlyCost(all), 1100 * rs);
    });

    test('deleting a subscription keeps its expenses', () async {
      final id = await spotify();
      await subs.markPaid(id);
      await subs.delete(id);
      expect(await subs.get(id), isNull);
      final all = await db.select(db.transactions).get();
      expect(all.length, 1);
      expect(all.single.subscriptionId, isNull);
    });

    test('validation', () {
      expect(
        () => subs.save(
          SubscriptionDraft(
            name: '',
            amount: 100,
            billingUnit: BillingUnit.month,
            nextDueDate: DateTime(2026, 12, 25),
            accountId: meezan,
          ),
        ),
        throwsA(isA<LedgerException>()),
      );
    });

    test('expenses linked to subscriptions are normal expenses in totals',
        () async {
      final id = await spotify();
      await subs.markPaid(id);
      final totals = await ledger.watchPeriodTotals(DateRange.all).first;
      expect(totals.moneyOut, 1100 * rs);
      expect(txs, isNotNull);
    });
  });

  group('custom reminders', () {
    test('next time for each repeat type', () {
      final at = DateTime(2026, 11, 25, 9, 30);
      expect(nextReminderTime(at: at, repeat: ReminderRepeat.none), isNull);
      expect(
        nextReminderTime(at: at, repeat: ReminderRepeat.daily),
        DateTime(2026, 11, 26, 9, 30),
      );
      expect(
        nextReminderTime(at: at, repeat: ReminderRepeat.weekly),
        DateTime(2026, 12, 2, 9, 30),
      );
      expect(
        nextReminderTime(at: at, repeat: ReminderRepeat.everyNDays, everyDays: 10),
        DateTime(2026, 12, 5, 9, 30),
      );
      expect(
        nextReminderTime(at: DateTime(2026, 12, 31, 8), repeat: ReminderRepeat.monthly),
        DateTime(2027, 1, 31, 8),
      );
      expect(
        nextReminderTime(
          at: DateTime(2027, 1, 31, 8),
          repeat: ReminderRepeat.monthly,
          anchorDay: 31,
        ),
        DateTime(2027, 2, 28, 8),
      );
    });

    test('repeating reminders roll forward, one-off ones stay', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = ReminderRepository(db);
      final weekly = await repo.save(
        ReminderDraft(
          title: 'Pay rent',
          remindAt: DateTime(2026, 11, 1, 9),
          repeat: ReminderRepeat.weekly,
        ),
      );
      final once = await repo.save(
        ReminderDraft(title: 'Call bank', remindAt: DateTime(2026, 11, 2, 9)),
      );
      final moved = await repo.rollForward(now: DateTime(2026, 11, 25, 12));
      expect(moved, 1);
      expect((await repo.get(weekly))!.remindAt, DateTime(2026, 11, 29, 9));
      expect((await repo.get(once))!.remindAt, DateTime(2026, 11, 2, 9));
      await db.close();
    });

    test('validation', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = ReminderRepository(db);
      expect(
        () => repo.save(ReminderDraft(title: ' ', remindAt: DateTime(2026, 11, 25))),
        throwsA(isA<LedgerException>()),
      );
      expect(
        () => repo.save(
          ReminderDraft(
            title: 'x',
            remindAt: DateTime(2026, 11, 25),
            repeat: ReminderRepeat.everyNDays,
          ),
        ),
        throwsA(isA<LedgerException>()),
      );
      await db.close();
    });
  });

  group('savings progress', () {
    test('ratio and remaining', () {
      expect(savingsProgress(balance: 22000, goal: 100000), 0.22);
      expect(savingsProgress(balance: 150000, goal: 100000), 1);
      expect(savingsProgress(balance: -5, goal: 100000), 0);
      expect(savingsProgress(balance: 5, goal: null), 0);
      expect(savingsRemaining(balance: 22000, goal: 100000), 78000);
      expect(savingsRemaining(balance: 150000, goal: 100000), 0);
    });
  });
}
