import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/home/data/dashboard_service.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

void main() {
  test('borrowed money is not counted as your own', () async {
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
    final person = await PersonRepository(
      db,
    ).save(const PersonDraft(name: 'Ali'));

    Future<(int, int)> totals() async {
      final accounts = await db.select(db.accounts).get();
      final inAccounts = LedgerService.headlineTotals(
        accounts,
        LedgerService.accountTotals(await LedgerService(db).sourceBalances()),
      ).total;
      final dues = await DashboardService(db).watchDueSummary().first;
      return (
        inAccounts,
        LedgerService.netBalance(
          inAccounts: inAccounts,
          borrowedOwed: dues.toPay,
        ),
      );
    }

    final due = await DueRepository(db).create(
      DueDraft(
        title: 'Loan',
        kind: DueKind.borrowed,
        personId: person,
        totalAmount: 500000,
        accountId: cash,
        dueDate: DateTime.now().add(const Duration(days: 10)),
      ),
    );
    // The cash is in the account, but it is not yours.
    expect(await totals(), (500000, 0));

    await TransactionRepository(db).save(
      TransactionInput(
        type: TransactionType.expense,
        amount: 500000,
        accountId: cash,
        categoryId: 'cat_exp_rent',
        date: DateTime.now(),
        allocations: const [AllocationInput('other_money', 500000)],
      ),
    );
    // All spent: the total goes negative by what is still owed.
    expect(await totals(), (0, -500000));

    // Paying it back moves cash and debt together.
    await DueRepository(db).recordPayment(due, amount: 100000, accountId: cash);
    expect(await totals(), (-100000, -500000));
  });
}
