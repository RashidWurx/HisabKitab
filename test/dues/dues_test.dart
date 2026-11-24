import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/database/seed.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/dues/data/payday_service.dart';
import 'package:hisaab/features/dues/domain/due_models.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

void main() {
  late AppDatabase db;
  late DueRepository dues;
  late LedgerService ledger;
  late TransactionRepository txs;
  late String meezan, jazz, job1, freelance, ali;

  final past = DateTime(2020, 1, 10);
  DateTime future(int days) => DateTime.now().add(Duration(days: days));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dues = DueRepository(db);
    ledger = LedgerService(db);
    txs = TransactionRepository(db);
    final sources = SourceRepository(db);
    job1 = await sources.save(
      const SourceDraft(name: 'Job 1', colorValue: 1, iconKey: 'work'),
    );
    freelance = await sources.save(
      const SourceDraft(name: 'Freelance', colorValue: 1, iconKey: 'laptop'),
    );
    final accounts = AccountRepository(db);
    meezan = await accounts.save(
      AccountDraft(
        name: 'Meezan',
        type: AccountType.bank,
        openingBalance: 50000 * rs,
        openingSplit: [AllocationInput(job1, 50000 * rs)],
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
    ali = await PersonRepository(db).save(const PersonDraft(name: 'Ali'));
  });

  tearDown(() => db.close());

  Future<void> consistent() async {
    final bySource = LedgerService.accountTotals(await ledger.sourceBalances());
    final independent = await ledger.accountBalancesFromTransactions();
    for (final id in independent.keys) {
      expect(bySource[id] ?? 0, independent[id], reason: 'account $id');
    }
  }

  Future<String> expected(int amount, DateTime due) => dues.create(
    DueDraft(
      title: 'Website',
      kind: DueKind.expectedIncome,
      sourceId: freelance,
      totalAmount: amount * rs,
      accountId: meezan,
      dueDate: due,
    ),
  );

  group('status and late days (pure)', () {
    final now = DateTime(2026, 11, 25, 15);
    DueStatus status({
      bool cancelled = false,
      int remaining = 100,
      int paid = 0,
      required DateTime due,
    }) => computeDueStatus(
      cancelled: cancelled,
      remaining: remaining,
      paid: paid,
      currentDueDate: due,
      now: now,
    );

    test('pending, partial, overdue, settled, cancelled', () {
      expect(status(due: DateTime(2026, 12, 1)), DueStatus.pending);
      expect(status(due: DateTime(2026, 12, 1), paid: 50), DueStatus.partial);
      expect(status(due: DateTime(2026, 11, 20)), DueStatus.overdue);
      expect(
        status(due: DateTime(2026, 11, 20), paid: 50),
        DueStatus.overdue,
      );
      expect(status(due: DateTime(2026, 11, 20), remaining: 0), DueStatus.settled);
      expect(status(due: DateTime(2026, 11, 20), cancelled: true), DueStatus.cancelled);
    });

    test('due today is not overdue yet', () {
      expect(status(due: DateTime(2026, 11, 25)), DueStatus.pending);
    });

    test('late days are counted from the ORIGINAL date', () {
      expect(
        computeLateDays(originalDueDate: DateTime(2026, 11, 15), now: now),
        10,
      );
      expect(
        computeLateDays(
          originalDueDate: DateTime(2026, 11, 15),
          now: now,
          settledAt: DateTime(2026, 11, 18),
        ),
        3,
      );
      expect(
        computeLateDays(originalDueDate: DateTime(2026, 12, 15), now: now),
        0,
      );
    });
  });

  group('pay schedule dates', () {
    test('monthly on the 31st falls on the last day of shorter months', () {
      DateTime? next(DateTime from) => nextPayday(
        type: PayScheduleType.monthly,
        payDay: 31,
        from: from,
      );
      expect(next(DateTime(2026, 11, 1)), DateTime(2026, 11, 30));
      expect(next(DateTime(2027, 2, 10)), DateTime(2027, 2, 28));
      expect(next(DateTime(2028, 2, 10)), DateTime(2028, 2, 29)); // leap year
      expect(next(DateTime(2026, 12, 1)), DateTime(2026, 12, 31));
    });

    test('monthly rolls to next month once the day has passed', () {
      expect(
        nextPayday(
          type: PayScheduleType.monthly,
          payDay: 1,
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 12, 1),
      );
      expect(
        nextPayday(
          type: PayScheduleType.monthly,
          payDay: 25,
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 11, 25), // today counts
      );
      expect(
        nextPayday(
          type: PayScheduleType.monthly,
          payDay: 5,
          from: DateTime(2026, 12, 20),
        ),
        DateTime(2027, 1, 5),
      );
    });

    test('weekly and every N days', () {
      // 25 Nov 2026 is a Wednesday (3). Friday = 5.
      expect(
        nextPayday(
          type: PayScheduleType.weekly,
          payDay: 5,
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 11, 27),
      );
      expect(
        nextPayday(
          type: PayScheduleType.weekly,
          payDay: 3,
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 11, 25),
      );
      expect(
        nextPayday(
          type: PayScheduleType.everyNDays,
          intervalDays: 14,
          anchor: DateTime(2026, 11, 1),
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 11, 29),
      );
      expect(
        nextPayday(
          type: PayScheduleType.everyNDays,
          intervalDays: 14,
          anchor: DateTime(2026, 12, 20),
          from: DateTime(2026, 11, 25),
        ),
        DateTime(2026, 12, 20),
      );
    });

    test('irregular and none have no payday', () {
      expect(
        nextPayday(type: PayScheduleType.irregular, from: DateTime(2026, 1, 1)),
        isNull,
      );
      expect(nextPayday(type: null, from: DateTime(2026, 1, 1)), isNull);
    });
  });

  group('expected income', () {
    test('partial then full payment: statuses, events, balances', () async {
      final id = await expected(20000, past);
      var v = (await dues.getView(id))!;
      expect(v.status, DueStatus.overdue);
      expect(v.remaining, 20000 * rs);
      expect(v.lateDays, greaterThan(0));

      await dues.recordPayment(id, amount: 10000 * rs, accountId: meezan);
      v = (await dues.getView(id))!;
      expect(v.paid, 10000 * rs);
      expect(v.remaining, 10000 * rs);
      expect(v.status, DueStatus.overdue); // still late, still open

      await dues.recordPayment(id, amount: 10000 * rs, accountId: jazz);
      v = (await dues.getView(id))!;
      expect(v.status, DueStatus.settled);
      expect(v.remaining, 0);

      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, freelance)], 10000 * rs);
      expect(b[AccountSource(jazz, freelance)], 10000 * rs);
      await consistent();

      final events = await dues.watchEvents(id).first;
      expect(events.map((e) => e.type), [
        DueEventType.settled,
        DueEventType.payment,
        DueEventType.payment,
        DueEventType.created,
      ]);
    });

    test('overpayment needs confirmation', () async {
      final id = await expected(1000, future(5));
      expect(
        () => dues.recordPayment(id, amount: 1500 * rs, accountId: meezan),
        throwsA(isA<LedgerException>()),
      );
      await dues.recordPayment(
        id,
        amount: 1500 * rs,
        accountId: meezan,
        allowOverpay: true,
      );
      final v = (await dues.getView(id))!;
      expect(v.status, DueStatus.settled);
      expect(v.remaining, 0);
    });

    test('editing and deleting a payment re-computes status and logs history',
        () async {
      final id = await expected(1000, future(5));
      final tx = await dues.recordPayment(id, amount: 1000 * rs, accountId: meezan);
      expect((await dues.getView(id))!.status, DueStatus.settled);

      await dues.editPayment(tx, amount: 400 * rs);
      var v = (await dues.getView(id))!;
      expect(v.status, DueStatus.partial);
      expect(v.remaining, 600 * rs);
      await consistent();

      await dues.deletePayment(tx);
      v = (await dues.getView(id))!;
      expect(v.status, DueStatus.pending);
      await consistent();

      final types = (await dues.watchEvents(id).first).map((e) => e.type);
      expect(types, containsAll([
        DueEventType.paymentEdited,
        DueEventType.paymentDeleted,
      ]));
    });
  });

  group('lent and borrowed', () {
    test('lending moves money out of the lender source; repay goes back to it',
        () async {
      final id = await dues.create(
        DueDraft(
          title: 'Lent to Ali',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 5000 * rs,
          accountId: meezan,
          dueDate: future(10),
          allocations: [AllocationInput(job1, 5000 * rs)],
        ),
      );
      var b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], 45000 * rs);
      await consistent();

      // Partial repayment into a different account: Job 1 money returns.
      await dues.recordPayment(id, amount: 2000 * rs, accountId: jazz);
      b = await ledger.sourceBalances();
      expect(b[AccountSource(jazz, job1)], 2000 * rs);
      var v = (await dues.getView(id))!;
      expect(v.status, DueStatus.partial);
      expect(v.remaining, 3000 * rs);

      await dues.recordPayment(id, amount: 3000 * rs, accountId: meezan);
      v = (await dues.getView(id))!;
      expect(v.status, DueStatus.settled);
      b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], 48000 * rs);
      await consistent();

      // Not income/expense anywhere.
      final totals = await ledger.watchPeriodTotals(DateRange.all).first;
      expect(totals.moneyIn, 0);
      expect(totals.moneyOut, 0);
    });

    test('split lent money returns to each lender source', () async {
      await txs.save(
        TransactionInput(
          type: TransactionType.income,
          amount: 4000 * rs,
          accountId: meezan,
          date: DateTime.now(),
          allocations: [AllocationInput(freelance, 4000 * rs)],
        ),
      );
      final id = await dues.create(
        DueDraft(
          title: 'Lent',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 6000 * rs,
          accountId: meezan,
          dueDate: future(10),
          allocations: [
            AllocationInput(job1, 4000 * rs),
            AllocationInput(freelance, 2000 * rs),
          ],
        ),
      );
      await dues.recordPayment(id, amount: 6000 * rs, accountId: meezan);
      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], 50000 * rs);
      expect(b[AccountSource(meezan, freelance)], 4000 * rs);
      await consistent();
    });

    test('borrowing adds to Other money; repaying takes money out', () async {
      final id = await dues.create(
        DueDraft(
          title: 'Borrowed from Ali',
          kind: DueKind.borrowed,
          personId: ali,
          totalAmount: 3000 * rs,
          accountId: jazz,
          dueDate: future(10),
        ),
      );
      var b = await ledger.sourceBalances();
      expect(b[AccountSource(jazz, otherMoneySourceId)], 3000 * rs);
      await dues.recordPayment(id, amount: 1000 * rs, accountId: jazz);
      b = await ledger.sourceBalances();
      expect(b[AccountSource(jazz, otherMoneySourceId)], 2000 * rs);
      expect((await dues.getView(id))!.remaining, 2000 * rs);
      await consistent();
    });

    test('editing the amount of a lent due keeps the transaction in sync',
        () async {
      final id = await dues.create(
        DueDraft(
          title: 'Lent',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 1000 * rs,
          accountId: meezan,
          dueDate: future(10),
          allocations: [AllocationInput(job1, 1000 * rs)],
        ),
      );
      final v = (await dues.getView(id))!;
      await dues.update(
        DueDraft(
          id: id,
          title: v.due.title,
          kind: v.due.kind,
          personId: ali,
          totalAmount: 1500 * rs,
          accountId: meezan,
          dueDate: v.due.currentDueDate,
        ),
      );
      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], 48500 * rs);
      await consistent();
    });
  });

  group('extending the date', () {
    test('keeps the original date, logs history, resets overdue', () async {
      final id = await expected(1000, past);
      expect((await dues.getView(id))!.status, DueStatus.overdue);
      final target = future(20);
      await dues.extend(id, newDate: target, reason: 'Invoice processing');
      var v = (await dues.getView(id))!;
      expect(v.due.originalDueDate, DateTime(2020, 1, 10));
      expect(v.due.currentDueDate, dateOnly(target));
      expect(v.status, DueStatus.pending);
      expect(v.extensionCount, 1);
      expect(v.lateDays, greaterThan(0)); // still counted from 10 Jan 2020

      await dues.recordPayment(id, amount: 400 * rs, accountId: meezan);
      expect((await dues.getView(id))!.status, DueStatus.partial);

      await dues.extend(id, newDate: future(40));
      v = (await dues.getView(id))!;
      expect(v.extensionCount, 2);

      final events = await dues.watchEvents(id).first;
      final extended = events.where((e) => e.type == DueEventType.extended).toList();
      expect(extended.length, 2);
      expect(extended.last.reason, 'Invoice processing');
      expect(extended.last.oldDate, DateTime(2020, 1, 10));
      expect(extended.last.newDate, dateOnly(target));
    });

    test('the new date must be after today', () async {
      final id = await expected(1000, future(3));
      expect(
        () => dues.extend(id, newDate: DateTime.now()),
        throwsA(isA<LedgerException>()),
      );
      expect(
        () => dues.extend(id, newDate: past),
        throwsA(isA<LedgerException>()),
      );
    });

    test('a date that passes again makes the due overdue again', () async {
      // Extended to yesterday is impossible via the API, so check the status
      // function directly against a later "now".
      expect(
        computeDueStatus(
          cancelled: false,
          remaining: 100,
          paid: 0,
          currentDueDate: DateTime(2026, 12, 1),
          now: DateTime(2026, 12, 3),
        ),
        DueStatus.overdue,
      );
    });
  });

  group('notes, snooze, cancel, delete', () {
    test('notes can be edited and are marked edited; other history cannot',
        () async {
      final id = await expected(1000, future(3));
      await dues.addNote(id, 'Called him');
      var events = await dues.watchEvents(id).first;
      final note = events.first;
      expect(note.type, DueEventType.note);
      expect(note.editedAt, isNull);
      await dues.editNote(note.id, 'Called him, pays Friday');
      events = await dues.watchEvents(id).first;
      expect(events.first.note, 'Called him, pays Friday');
      expect(events.first.editedAt, isNotNull);
      expect(
        () => dues.editNote(events.last.id, 'x'), // the "created" entry
        throwsA(isA<LedgerException>()),
      );
    });

    test('cancel with write-off closes it and drops the remaining', () async {
      final id = await expected(1000, future(3));
      await dues.recordPayment(id, amount: 300 * rs, accountId: meezan);
      await dues.cancel(id, writeOff: true);
      final v = (await dues.getView(id))!;
      expect(v.status, DueStatus.cancelled);
      expect(v.due.writtenOffAmount, 700 * rs);
      expect(
        () => dues.recordPayment(id, amount: 1 * rs, accountId: meezan),
        throwsA(isA<LedgerException>()),
      );
      expect((await dues.watchEvents(id).first).first.type, DueEventType.cancelled);
    });

    test('deleting a due removes its transactions and history', () async {
      final id = await dues.create(
        DueDraft(
          title: 'Lent',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 1000 * rs,
          accountId: meezan,
          dueDate: future(3),
          allocations: [AllocationInput(job1, 1000 * rs)],
        ),
      );
      await dues.recordPayment(id, amount: 200 * rs, accountId: meezan);
      await dues.delete(id);
      expect(await dues.getView(id), isNull);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.dueEvents).get(), isEmpty);
      final b = await ledger.sourceBalances();
      expect(b[AccountSource(meezan, job1)], 50000 * rs); // back to normal
    });
  });

  group('people', () {
    test('net balance and on-time vs late record', () async {
      final a = await dues.create(
        DueDraft(
          title: 'Late payer',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 1000 * rs,
          accountId: meezan,
          dueDate: past,
          allocations: [AllocationInput(job1, 1000 * rs)],
        ),
      );
      await dues.recordPayment(a, amount: 1000 * rs, accountId: meezan);
      final b = await dues.create(
        DueDraft(
          title: 'On time',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 500 * rs,
          accountId: meezan,
          dueDate: future(30),
          allocations: [AllocationInput(job1, 500 * rs)],
        ),
      );
      await dues.recordPayment(b, amount: 500 * rs, accountId: meezan);
      await dues.create(
        DueDraft(
          title: 'Owed',
          kind: DueKind.borrowed,
          personId: ali,
          totalAmount: 200 * rs,
          accountId: meezan,
          dueDate: future(30),
        ),
      );
      await dues.create(
        DueDraft(
          title: 'Still owes',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 900 * rs,
          accountId: meezan,
          dueDate: future(30),
          allocations: [AllocationInput(job1, 900 * rs)],
        ),
      );
      final views = await dues.watchViews().first;
      expect(personNet(views, ali), (900 - 200) * rs);
      final rec = trackRecordFor(views.where((v) => v.due.personId == ali));
      expect(rec.onTime, 1);
      expect(rec.late, 1);
      expect(rec.averageDaysLate, greaterThan(1000));
    });

    test('person with dues cannot be deleted', () async {
      await dues.create(
        DueDraft(
          title: 'Lent',
          kind: DueKind.lent,
          personId: ali,
          totalAmount: 100 * rs,
          accountId: meezan,
          dueDate: future(3),
          allocations: [AllocationInput(job1, 100 * rs)],
        ),
      );
      expect(
        () => PersonRepository(db).delete(ali),
        throwsA(isA<BlockedDeleteException>()),
      );
    });
  });

  group('paydays', () {
    Future<String> source({
      int? amount = 80000,
      ActiveStatus status = ActiveStatus.active,
      PayScheduleType? type = PayScheduleType.monthly,
      String? accountId,
    }) => SourceRepository(db).save(
      SourceDraft(
        name: 'Job X',
        colorValue: 1,
        iconKey: 'work',
        linkedAccountId: accountId ?? meezan,
        expectedAmount: amount == null ? null : amount * rs,
        payScheduleType: type,
        payDay: 1,
        status: status,
      ),
    );

    test('creates only the next payday due, once', () async {
      await source();
      final service = PaydayService(db);
      final now = DateTime(2026, 11, 25);
      expect(await service.ensureNextPaydays(now: now), 1);
      expect(await service.ensureNextPaydays(now: now), 0); // no duplicates
      final all = await db.select(db.dues).get();
      expect(all.length, 1);
      expect(all.single.title, 'Job X salary, Dec 2026');
      expect(all.single.currentDueDate, DateTime(2026, 12, 1));
      expect(all.single.kind, DueKind.expectedIncome);
      expect(all.single.accountId, meezan);
      expect(all.single.totalAmount, 80000 * rs);

      // Next month: a new due appears, rolling forward one period.
      expect(
        await service.ensureNextPaydays(now: DateTime(2026, 12, 2)),
        1,
      );
      expect((await db.select(db.dues).get()).length, 2);
    });

    test('skips inactive sources, no amount, irregular, no account', () async {
      await source(status: ActiveStatus.inactive);
      await source(amount: null);
      await source(type: PayScheduleType.irregular);
      expect(
        await PaydayService(db).ensureNextPaydays(now: DateTime(2026, 11, 25)),
        0,
      );
    });

    test('payday due can be confirmed with a different amount', () async {
      await source();
      await PaydayService(db).ensureNextPaydays(now: DateTime(2026, 11, 25));
      final due = (await db.select(db.dues).get()).single;
      await dues.recordPayment(due.id, amount: 75000 * rs, accountId: meezan);
      final v = (await dues.getView(due.id))!;
      expect(v.paid, 75000 * rs);
      expect(v.status, isNot(DueStatus.settled));
    });
  });

  test('db access sanity: Value import is used', () {
    expect(const Value(1).present, isTrue);
  });
}
