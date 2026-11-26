import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/home/data/dashboard_service.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/notifications/domain/notification_models.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/thirdparty/data/pass_repository.dart';
import 'package:hisaab/features/thirdparty/domain/pass_models.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

void main() {
  late AppDatabase db;
  late PassRepository repo;
  late String bank, job, ali, bilal;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = PassRepository(db);
    job = await SourceRepository(db).save(
      const SourceDraft(name: 'Job', colorValue: 1, iconKey: 'work'),
    );
    bank = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: 0,
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
    await TransactionRepository(db).save(
      TransactionInput(
        type: TransactionType.income,
        amount: 20000 * rs,
        accountId: bank,
        date: DateTime(2026, 11, 1),
        allocations: [AllocationInput(job, 20000 * rs)],
      ),
    );
    final people = PersonRepository(db);
    ali = await people.save(const PersonDraft(name: 'Ali'));
    bilal = await people.save(const PersonDraft(name: 'Bilal'));
  });
  tearDown(() => db.close());

  PassDraft draft({
    String? id,
    bool throughMe = true,
    bool handedOver = true,
    int amount = 10000 * rs,
    String? note,
    DateTime? collectBy,
    DateTime? returnBy,
  }) => PassDraft(
    id: id,
    fromPersonId: ali,
    forPersonId: bilal,
    amount: amount,
    date: DateTime(2026, 11, 5),
    throughMe: throughMe,
    accountId: throughMe ? bank : null,
    handedOver: handedOver,
    note: note,
    collectBy: collectBy,
    returnBy: returnBy,
  );

  Future<Map<AccountSource, int>> balances() =>
      LedgerService(db).sourceBalances();
  Future<int> inBank() async =>
      LedgerService.accountTotals(await balances())[bank] ?? 0;
  Future<int> fromJob() async =>
      LedgerService.sourceTotals(await balances())[job] ?? 0;

  /// The Home headline.
  Future<int> myTotal() async => LedgerService.netBalance(
    inAccounts: await inBank(),
    borrowedOwed: 0,
    heldForOthers: PassSummary.of(await repo.views()).heldInTotal,
  );

  Future<void> expectNotIncomeOrExpense() async {
    final totals = await LedgerService(db)
        .watchPeriodTotals(DateRange.all)
        .first;
    expect(totals.moneyIn, 20000 * rs);
    expect(totals.moneyOut, 0);
    final dues = await DashboardService(db).watchDueSummary().first;
    expect((dues.toPay, dues.toReceive), (0, 0));
  }

  test('money passing through leaves my own numbers alone', () async {
    final id = await repo.create(draft(handedOver: false));
    expect(await inBank(), 30000 * rs);
    expect(await myTotal(), 20000 * rs);

    await repo.record(
      id,
      PassAction.handOver,
      amount: 10000 * rs,
      accountId: bank,
    );
    expect(await myTotal(), 20000 * rs);

    // Bilal returns part, I hold it, then pass it on.
    await repo.record(
      id,
      PassAction.collect,
      amount: 4000 * rs,
      accountId: bank,
    );
    expect(await inBank(), 24000 * rs);
    expect(await myTotal(), 20000 * rs);
    await repo.record(
      id,
      PassAction.payBack,
      amount: 4000 * rs,
      accountId: bank,
    );

    final v = (await repo.view(id))!;
    expect((v.toCollect, v.toPayBack), (6000 * rs, 6000 * rs));
    expect(v.entries, hasLength(4));
    expect(await myTotal(), 20000 * rs);
    expect(await fromJob(), 20000 * rs);
    await expectNotIncomeOrExpense();
  });

  test('paying the lender first comes from me and comes back', () async {
    final id = await repo.create(draft());

    await repo.record(
      id,
      PassAction.payBack,
      amount: 10000 * rs,
      accountId: bank,
    );
    var v = (await repo.view(id))!;
    expect(v.covered, 10000 * rs);
    expect((v.toCollect, v.toPayBack), (10000 * rs, 0));
    expect(v.isOpen, isTrue);
    expect(await myTotal(), 10000 * rs);
    expect(await fromJob(), 10000 * rs);

    await repo.record(
      id,
      PassAction.collect,
      amount: 10000 * rs,
      accountId: bank,
    );
    v = (await repo.view(id))!;
    expect(v.isOpen, isFalse);
    expect(await myTotal(), 20000 * rs);
    expect(await fromJob(), 20000 * rs);
    await expectNotIncomeOrExpense();
  });

  test('directly between them never touches an account', () async {
    final id = await repo.create(draft(throughMe: false));
    expect(await db.select(db.transactions).get(), hasLength(1));
    var v = (await repo.view(id))!;
    expect((v.toCollect, v.toPayBack), (10000 * rs, 10000 * rs));

    await repo.record(id, PassAction.direct, amount: 10000 * rs);
    v = (await repo.view(id))!;
    expect(v.isOpen, isFalse);
    expect(await inBank(), 20000 * rs);
  });

  test('impossible steps are refused', () async {
    final id = await repo.create(draft(handedOver: false));
    Future<void> refused(PassAction a, int amount) => expectLater(
      repo.record(id, a, amount: amount, accountId: bank),
      throwsA(isA<LedgerException>()),
    );
    await refused(PassAction.collect, rs); // Bilal has nothing yet
    await refused(PassAction.payBack, rs); // not handed over yet
    await refused(PassAction.handOver, 10001 * rs);
    await expectLater(
      repo.create(
        PassDraft(
          fromPersonId: ali,
          forPersonId: ali,
          amount: rs,
          date: DateTime(2026),
          throughMe: false,
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
  });

  test('steps can be removed and records deleted without leftovers', () async {
    final id = await repo.create(draft(handedOver: false));
    await repo.record(
      id,
      PassAction.handOver,
      amount: 10000 * rs,
      accountId: bank,
    );
    await repo.record(
      id,
      PassAction.collect,
      amount: 4000 * rs,
      accountId: bank,
    );
    var v = (await repo.view(id))!;
    String entry(PassEntryKind k) => v.entries.firstWhere((e) => e.kind == k).id;

    // Not while a later step depends on it, and never the first one.
    await expectLater(
      repo.deleteEntry(entry(PassEntryKind.givenOut)),
      throwsA(isA<LedgerException>()),
    );
    await expectLater(
      repo.deleteEntry(entry(PassEntryKind.takenIn)),
      throwsA(isA<LedgerException>()),
    );
    await repo.deleteEntry(entry(PassEntryKind.collected));
    v = (await repo.view(id))!;
    expect(v.toCollect, 10000 * rs);

    await expectLater(
      PersonRepository(db).delete(ali),
      throwsA(isA<BlockedDeleteException>()),
    );
    await repo.delete(id);
    expect(await inBank(), 20000 * rs);
    expect(await db.select(db.passEntries).get(), isEmpty);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('the amount can be corrected only before a later step', () async {
    final id = await repo.create(draft(handedOver: false));
    await repo.update(draft(id: id, handedOver: false, amount: 8000 * rs));
    expect((await repo.view(id))!.amount, 8000 * rs);
    expect(await inBank(), 28000 * rs);

    await repo.record(
      id,
      PassAction.handOver,
      amount: 3000 * rs,
      accountId: bank,
    );
    // The note can change and the history stays.
    await repo.update(
      draft(id: id, amount: 8000 * rs, handedOver: false, note: 'School fee'),
    );
    final v = (await repo.view(id))!;
    expect(v.pass.note, 'School fee');
    expect(v.entries, hasLength(2));
    expect(v.toHandOver, 5000 * rs);

    await expectLater(
      repo.update(draft(id: id, amount: 9000 * rs)),
      throwsA(isA<LedgerException>()),
    );
    expect((await repo.view(id))!.entries, hasLength(2));
  });

  test('reminds to collect and to return, and shows in Upcoming', () async {
    await repo.create(
      draft(
        collectBy: DateTime(2026, 12, 10),
        returnBy: DateTime(2026, 12, 12),
      ),
    );
    final people = await db.select(db.people).get();
    final plan = planReminders(
      PlanInput(
        now: DateTime(2026, 12, 1),
        prefs: NotificationPrefs.defaults,
        people: {for (final p in people) p.id: p},
        passes: await repo.views(),
      ),
    );
    expect(plan.every((r) => r.payload.startsWith('pass:')), isTrue);
    expect(
      plan.first.body,
      'Collect Rs 10,000 from Bilal (to return to Ali). Due tomorrow.',
    );
    expect(plan.map((r) => r.at), contains(DateTime(2026, 12, 12, 9)));

    final upcoming = await DashboardService(db)
        .watchUpcoming(now: DateTime(2026, 12, 9))
        .first;
    expect(upcoming.map((u) => u.kind), [
      UpcomingKind.collect,
      UpcomingKind.payBack,
    ]);
    expect(upcoming.map((u) => u.amount), [10000 * rs, 10000 * rs]);
  });
}
