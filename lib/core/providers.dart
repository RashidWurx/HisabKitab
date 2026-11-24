import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/accounts/data/account_repository.dart';
import '../features/categories/data/category_repository.dart';
import '../features/ledger/data/ledger_service.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/sources/data/source_repository.dart';
import '../features/transactions/data/transaction_repository.dart';
import '../features/transactions/domain/transaction_models.dart';
import 'database/app_database.dart';
import 'database/database_provider.dart';

final accountRepositoryProvider = Provider(
  (ref) => AccountRepository(ref.watch(databaseProvider)),
);
final sourceRepositoryProvider = Provider(
  (ref) => SourceRepository(ref.watch(databaseProvider)),
);
final categoryRepositoryProvider = Provider(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);
final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(ref.watch(databaseProvider)),
);
final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);
final ledgerProvider = Provider(
  (ref) => LedgerService(ref.watch(databaseProvider)),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(),
);
final sourcesProvider = StreamProvider<List<IncomeSource>>(
  (ref) => ref.watch(sourceRepositoryProvider).watchAll(),
);
final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
final settingsProvider = StreamProvider<AppSettingsData>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Money of each source in each account (all balances derive from this).
final sourceBalancesProvider = StreamProvider<Map<AccountSource, int>>(
  (ref) => ref.watch(ledgerProvider).watchSourceBalances(),
);

final transactionsProvider =
    StreamProvider.family<List<Transaction>, TransactionFilter>(
      (ref, filter) => ref.watch(transactionRepositoryProvider).watch(filter),
    );

typedef PeriodKey = (DateRange, String?);

final periodTotalsProvider =
    StreamProvider.family<AccountPeriodStats, PeriodKey>(
      (ref, key) => ref
          .watch(ledgerProvider)
          .watchPeriodTotals(key.$1, accountId: key.$2),
    );

final sourceStatsProvider =
    StreamProvider.family<SourcePeriodStats, (String, DateRange)>(
      (ref, key) =>
          ref.watch(ledgerProvider).watchSourceStats(key.$1, key.$2),
    );

typedef SpendKey = (DateRange, String?, String?);

/// (range, accountId, sourceId)
final spendingByCategoryProvider =
    StreamProvider.family<List<CategorySpend>, SpendKey>(
      (ref, key) => ref
          .watch(ledgerProvider)
          .watchSpendingByCategory(
            key.$1,
            accountId: key.$2,
            sourceId: key.$3,
          ),
    );
