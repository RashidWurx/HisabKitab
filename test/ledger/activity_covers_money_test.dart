import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/reminders/data/reminder_repository.dart';
import 'package:hisaab/features/subscriptions/data/subscription_repository.dart';
import 'package:hisaab/features/thirdparty/data/pass_repository.dart';
import 'package:hisaab/features/thirdparty/domain/pass_activity.dart';
import 'package:hisaab/features/thirdparty/domain/pass_models.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';

const rs = 100;

void main() {
  test('every movement of money is listed in Activity', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final bank = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: 100000 * rs,
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
    final people = PersonRepository(db);
    final ali = await people.save(const PersonDraft(name: 'Ali'));
    final bilal = await people.save(const PersonDraft(name: 'Bilal'));
    final now = DateTime.now();

    Future<int> balance() async => LedgerService.accountTotals(
      await LedgerService(db).sourceBalances(),
    )[bank]!;
    Future<List<Transaction>> activity() => TransactionRepository(
      db,
    ).watch(const TransactionFilter()).first;

    // A planned payment moves nothing until it is paid.
    final reminders = ReminderRepository(db);
    final planned = await reminders.save(
      ReminderDraft(title: 'Siblings', amount: 5000 * rs, remindAt: now),
    );
    expect(await activity(), isEmpty);
    await reminders.payNow(
      planned,
      occurrence: (await reminders.get(planned))!.remindAt,
      amount: 5000 * rs,
      accountId: bank,
      categoryId: 'cat_exp_rent',
      date: now,
    );
    expect(await balance(), 95000 * rs);
    expect((await activity()).single.note, 'Siblings');

    // Borrowing and paying part of it back.
    final dues = DueRepository(db);
    final due = await dues.create(
      DueDraft(
        title: 'Loan',
        kind: DueKind.borrowed,
        personId: ali,
        totalAmount: 1000 * rs,
        accountId: bank,
        dueDate: now,
      ),
    );
    await dues.recordPayment(due, amount: 400 * rs, accountId: bank);

    // A subscription renewal.
    final subs = SubscriptionRepository(db);
    final sub = await subs.save(
      SubscriptionDraft(
        name: 'VPS',
        amount: 100 * rs,
        billingUnit: BillingUnit.month,
        nextDueDate: now,
        accountId: bank,
      ),
    );
    await subs.markPaid(sub, amount: 100 * rs, date: now);

    // 3rd party money, through the account and straight between them.
    final passes = PassRepository(db);
    Future<String> pass(bool throughMe) => passes.create(
      PassDraft(
        fromPersonId: ali,
        forPersonId: bilal,
        amount: 200 * rs,
        date: now,
        throughMe: throughMe,
        accountId: throughMe ? bank : null,
      ),
    );
    await pass(true);
    final direct = await pass(false);
    await passes.record(direct, PassAction.direct, amount: 50 * rs);

    final rows = await activity();
    expect(
      rows.map((t) => t.type),
      containsAll([
        TransactionType.expense,
        TransactionType.borrowIn,
        TransactionType.repayOut,
        TransactionType.passIn,
        TransactionType.passOut,
      ]),
    );
    expect(rows, hasLength(6));
    final moves = directMoves(
      await passes.views(),
      await db.select(db.people).get(),
      const TransactionFilter(),
    );
    expect(moves.map((m) => m.entry.amount).toSet(), {200 * rs, 50 * rs});
    expect(
      directMoves(
        await passes.views(),
        await db.select(db.people).get(),
        TransactionFilter(accountId: bank),
      ),
      isEmpty,
    );
  });

  test('paying from an empty account still works and goes below zero', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cash = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Cash',
        type: AccountType.cash,
        openingBalance: 0,
        colorValue: 1,
        iconKey: 'cash',
      ),
    );
    final reminders = ReminderRepository(db);
    final now = DateTime.now();
    final id = await reminders.save(
      ReminderDraft(title: 'Siblings', amount: 5000 * rs, remindAt: now),
    );
    await reminders.payNow(
      id,
      occurrence: (await reminders.get(id))!.remindAt,
      amount: 5000 * rs,
      accountId: cash,
      categoryId: 'cat_exp_rent',
      date: now,
    );
    final balances = await LedgerService(db).sourceBalances();
    expect(LedgerService.accountTotals(balances)[cash], -5000 * rs);
  });
}
