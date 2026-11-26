import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/dues/domain/due_models.dart';
import 'package:hisaab/features/home/data/dashboard_service.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';

void main() {
  test('money still to be received is not part of the total balance', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final account = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: 100000,
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
    await DueRepository(db).create(
      DueDraft(
        title: 'Salary',
        kind: DueKind.expectedIncome,
        totalAmount: 5000000,
        accountId: account,
        dueDate: DateTime.now().add(const Duration(days: 5)),
      ),
    );

    final ledger = LedgerService(db);
    final accounts = await db.select(db.accounts).get();
    final headline = LedgerService.headlineTotals(
      accounts,
      LedgerService.accountTotals(await ledger.sourceBalances()),
    );
    final dues = await DashboardService(db).watchDueSummary().first;

    expect(headline.total, 100000);
    expect(dues.toReceive, 5000000);
  });
}
