import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/accounts/data/account_repository.dart';
import '../features/categories/data/category_repository.dart';
import '../features/dues/data/due_repository.dart';
import '../features/dues/data/payday_service.dart';
import '../features/dues/domain/due_models.dart';
import '../features/ledger/data/ledger_service.dart';
import '../features/people/data/person_repository.dart';
import '../features/reminders/data/reminder_repository.dart';
import '../features/subscriptions/data/subscription_repository.dart';
import '../features/thirdparty/data/pass_repository.dart';
import '../features/thirdparty/domain/pass_models.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/sources/data/source_repository.dart';
import '../features/transactions/data/transaction_repository.dart';
import '../features/transactions/domain/transaction_models.dart';
import 'database/app_database.dart';
import 'database/database_provider.dart';
import 'utils/period.dart';

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

final dueRepositoryProvider = Provider(
  (ref) => DueRepository(ref.watch(databaseProvider)),
);
final personRepositoryProvider = Provider(
  (ref) => PersonRepository(ref.watch(databaseProvider)),
);
final paydayServiceProvider = Provider(
  (ref) => PaydayService(ref.watch(databaseProvider)),
);

final subscriptionRepositoryProvider = Provider(
  (ref) => SubscriptionRepository(ref.watch(databaseProvider)),
);
final reminderRepositoryProvider = Provider(
  (ref) => ReminderRepository(ref.watch(databaseProvider)),
);

final passRepositoryProvider = Provider(
  (ref) => PassRepository(ref.watch(databaseProvider)),
);

/// Every 3rd party record with its history.
final passViewsProvider = StreamProvider<List<PassView>>(
  (ref) => ref.watch(passRepositoryProvider).watchViews(),
);
final passSummaryProvider = Provider<PassSummary>(
  (ref) => PassSummary.of(ref.watch(passViewsProvider).value ?? const []),
);

final subscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(subscriptionRepositoryProvider).watchAll(),
);
final remindersProvider = StreamProvider<List<CustomReminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchAll(),
);

/// Spent on subscriptions (null id = all subscriptions).
final subscriptionSpendProvider =
    StreamProvider.family<SubscriptionSpend, String?>((ref, id) {
      final startDay = ref.watch(
        settingsProvider.select((s) => s.value?.monthStartDay ?? 1),
      );
      return ref
          .watch(subscriptionRepositoryProvider)
          .watchSpend(
            subscriptionId: id,
            monthStart: rangeFor(
              PeriodKind.thisMonth,
              monthStartDay: startDay,
            ).start,
          );
    });
final subscriptionPaymentsProvider =
    StreamProvider.family<List<Transaction>, String>(
      (ref, id) => ref.watch(subscriptionRepositoryProvider).watchPayments(id),
    );

final peopleProvider = StreamProvider<List<PeopleData>>(
  (ref) => ref.watch(personRepositoryProvider).watchAll(),
);

/// Every due with its computed status, paid and remaining amounts.
final dueViewsProvider = StreamProvider<List<DueView>>(
  (ref) => ref.watch(dueRepositoryProvider).watchViews(),
);
final dueViewProvider = StreamProvider.family<DueView?, String>(
  (ref, id) => ref.watch(dueRepositoryProvider).watchView(id),
);
final dueEventsProvider = StreamProvider.family<List<DueEvent>, String>(
  (ref, id) => ref.watch(dueRepositoryProvider).watchEvents(id),
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
