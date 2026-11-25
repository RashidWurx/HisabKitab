import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

/// Long random sequences of every transaction kind, with edits and deletes.
/// After EVERY step: per account the source balances sum to the account
/// balance computed independently from the transactions, and every saved
/// transaction's allocations sum exactly to its amount.
void main() {
  for (final seed in [1, 7, 42]) {
    test('invariants hold over 120 random operations (seed $seed)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final accounts = AccountRepository(db);
      final sources = SourceRepository(db);
      final txs = TransactionRepository(db);
      final ledger = LedgerService(db);
      final rnd = Random(seed);
      final day = DateTime(2026, 11, 24);

      final srcIds = [
        await sources.save(const SourceDraft(name: 'A', colorValue: 1, iconKey: 'work')),
        await sources.save(const SourceDraft(name: 'B', colorValue: 1, iconKey: 'laptop')),
        await sources.save(const SourceDraft(name: 'C', colorValue: 1, iconKey: 'work')),
      ];
      final accIds = [
        for (final name in ['One', 'Two', 'Three'])
          await accounts.save(
            AccountDraft(
              name: name,
              type: AccountType.bank,
              openingBalance: 1000 * rs,
              openingSplit: [AllocationInput(srcIds[0], 400 * rs)],
              colorValue: 1,
              iconKey: 'bank',
            ),
          ),
      ];
      final saved = <String>[];

      String pick(List<String> l) => l[rnd.nextInt(l.length)];

      // Split [amount] over 1-3 random sources, summing exactly.
      List<AllocationInput> split(int amount) {
        final n = 1 + rnd.nextInt(3);
        final chosen = (List.of(srcIds)..shuffle(rnd)).take(n).toList();
        var left = amount;
        final out = <AllocationInput>[];
        for (var i = 0; i < chosen.length; i++) {
          final part = i == chosen.length - 1
              ? left
              : (left == 0 ? 0 : rnd.nextInt(left + 1));
          if (part > 0) out.add(AllocationInput(chosen[i], part));
          left -= part;
        }
        return out;
      }

      TransactionInput make(int amount) {
        final account = pick(accIds);
        final kind = rnd.nextInt(5);
        final allocations = split(amount);
        switch (kind) {
          case 0:
            return TransactionInput(
              type: TransactionType.income,
              amount: amount,
              accountId: account,
              date: day,
              allocations: allocations,
            );
          case 1:
            return TransactionInput(
              type: TransactionType.expense,
              amount: amount,
              accountId: account,
              categoryId: 'cat_exp_rent',
              date: day,
              allocations: allocations,
            );
          case 2:
            final other = pick(accIds.where((a) => a != account).toList());
            return TransactionInput(
              type: TransactionType.transfer,
              amount: amount,
              accountId: account,
              toAccountId: other,
              date: day,
              allocations: allocations,
            );
          case 3:
            return TransactionInput(
              type: TransactionType.lendOut,
              amount: amount,
              accountId: account,
              date: day,
              allocations: allocations,
            );
          default:
            return TransactionInput(
              type: TransactionType.repayIn,
              amount: amount,
              accountId: account,
              date: day,
              allocations: allocations,
            );
        }
      }

      Future<void> check(String step) async {
        final bySource = LedgerService.accountTotals(
          await ledger.sourceBalances(),
        );
        final independent = await ledger.accountBalancesFromTransactions();
        for (final id in independent.keys) {
          expect(bySource[id] ?? 0, independent[id], reason: '$step: account');
        }
        final rows = await db.select(db.transactions).get();
        final allocs = await db.select(db.transactionAllocations).get();
        for (final t in rows) {
          final sum = allocs
              .where((a) => a.transactionId == t.id)
              .fold<int>(0, (s, a) => s + a.amount);
          // Transfers allocate the moved amount once; every other kind too.
          expect(sum, t.amount, reason: '$step: allocations of ${t.id}');
        }
      }

      for (var step = 0; step < 120; step++) {
        final action = rnd.nextInt(10);
        if (action < 6 || saved.isEmpty) {
          final id = await txs.save(make(1 + rnd.nextInt(500 * rs)));
          saved.add(id);
        } else if (action < 8) {
          final id = pick(saved);
          final current = (await txs.get(id))!;
          final amount = 1 + rnd.nextInt(500 * rs);
          await txs.save(
            current.copyWith(amount: amount, allocations: split(amount)),
          );
        } else {
          final id = pick(saved);
          saved.remove(id);
          await txs.delete(id);
        }
        await check('seed $seed step $step');
      }
    });
  }
}
