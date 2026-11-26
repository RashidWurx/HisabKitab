import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/accounts/presentation/account_detail_page.dart';
import '../../features/accounts/presentation/account_form_page.dart';
import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/categories/presentation/category_form_page.dart';
import '../../features/dues/presentation/due_detail_page.dart';
import '../../features/dues/presentation/due_form_page.dart';
import '../../features/dues/presentation/dues_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/people/presentation/people_pages.dart';
import '../../features/more/presentation/more_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/reminders/presentation/reminders_page.dart';
import '../../features/thirdparty/presentation/third_party_detail_page.dart';
import '../../features/thirdparty/presentation/third_party_form_page.dart';
import '../../features/thirdparty/presentation/third_party_page.dart';
import '../../features/savings/presentation/savings_page.dart';
import '../../features/subscriptions/presentation/subscription_detail_page.dart';
import '../../features/subscriptions/presentation/subscription_form_page.dart';
import '../../features/subscriptions/presentation/subscriptions_page.dart';
import '../../features/applock/presentation/app_lock_page.dart';
import '../../features/backup/presentation/backup_page.dart';
import '../../features/notifications/presentation/missed_page.dart';
import '../../features/notifications/presentation/notification_settings_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/sources/presentation/source_detail_page.dart';
import '../../features/sources/presentation/source_form_page.dart';
import '../../features/sources/presentation/sources_page.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/transactions/presentation/activity_page.dart';
import '../../features/transactions/presentation/transaction_form_page.dart';
import '../database/enums.dart';
import '../providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Full-screen routes (no bottom nav) use the root navigator.
GoRoute _full(String path, Widget Function(GoRouterState s) builder) =>
    GoRoute(
      path: path,
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, state) => builder(state),
    );

final routerProvider = Provider<GoRouter>((ref) {
  // Tells the router to re-run `redirect` when settings (onboarding) change.
  final refresh = ValueNotifier<int>(0);
  // Only the onboarding flag matters here; theme/other settings must not
  // make the router re-run (that would rebuild screens needlessly).
  ref.listen(
    settingsProvider.select((s) => s.hasValue ? s.requireValue.onboardingDone : null),
    (_, _) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      final loc = state.matchedLocation;
      if (!settings.hasValue) return loc == '/splash' ? null : '/splash';
      final done = settings.requireValue.onboardingDone;
      if (!done && loc != '/onboarding') return '/onboarding';
      if (done && loc == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      _full('/onboarding', (_) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, state) {
                  final account = state.uri.queryParameters['account'];
                  return ActivityPage(
                    key: ValueKey(account),
                    initialFilter: account == null
                        ? null
                        : TransactionFilter(accountId: account),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dues',
                builder: (_, state) => DuesPage(
                  key: ValueKey(state.uri.queryParameters['tab']),
                  initialTab: state.uri.queryParameters['tab'] == 'pay' ? 1 : 0,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/subscriptions',
                builder: (_, _) => const SubscriptionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (_, _) => const MorePage()),
            ],
          ),
        ],
      ),
      _full('/accounts', (_) => const AccountsPage()),
      _full(
        '/accounts/new',
        (s) => AccountFormPage(
          initialType: s.uri.queryParameters['type'] == 'savings'
              ? AccountType.savings
              : null,
        ),
      ),
      _full(
        '/accounts/:id',
        (s) => AccountDetailPage(accountId: s.pathParameters['id']!),
      ),
      _full(
        '/accounts/:id/edit',
        (s) => AccountFormPage(accountId: s.pathParameters['id']),
      ),
      _full('/sources', (_) => const SourcesPage()),
      _full('/sources/new', (_) => const SourceFormPage()),
      _full(
        '/sources/:id',
        (s) => SourceDetailPage(sourceId: s.pathParameters['id']!),
      ),
      _full(
        '/sources/:id/edit',
        (s) => SourceFormPage(sourceId: s.pathParameters['id']),
      ),
      _full('/categories', (_) => const CategoriesPage()),
      _full(
        '/categories/new',
        (s) => CategoryFormPage(
          kind: s.uri.queryParameters['kind'] == 'income'
              ? CategoryKind.income
              : CategoryKind.expense,
        ),
      ),
      _full(
        '/categories/:id/edit',
        (s) => CategoryFormPage(categoryId: s.pathParameters['id']),
      ),
      _full(
        '/transaction/new/:type',
        (s) => TransactionFormPage(
          prefillAmount: int.tryParse(s.uri.queryParameters['amount'] ?? ''),
          prefillCategoryId: s.uri.queryParameters['category'],
          prefillAccountId: s.uri.queryParameters['account'],
          fromAccountId: s.uri.queryParameters['from'],
          toAccountId: s.uri.queryParameters['to'],
          prefillNote: s.uri.queryParameters['note'],
          reminderId: s.uri.queryParameters['reminder'],
          occurrence: switch (int.tryParse(
            s.uri.queryParameters['occurrence'] ?? '',
          )) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
            null => null,
          },
          type: switch (s.pathParameters['type']) {
            'income' => TransactionType.income,
            'transfer' => TransactionType.transfer,
            _ => TransactionType.expense,
          },
        ),
      ),
      _full(
        '/transaction/:id/edit',
        (s) => TransactionFormPage(transactionId: s.pathParameters['id']),
      ),
      _full('/settings', (_) => const SettingsPage()),
      _full('/backup', (_) => const BackupPage()),
      _full('/notifications', (_) => const MissedPage()),
      _full('/settings/app-lock', (_) => const AppLockPage()),
      _full('/settings/app-lock/setup', (_) => const PinSetupPage()),
      _full(
        '/settings/notifications',
        (_) => const NotificationSettingsPage(),
      ),
      _full(
        '/subscriptions/new',
        (s) => SubscriptionFormPage(initialName: s.uri.queryParameters['name']),
      ),
      _full(
        '/subscriptions/:id',
        (s) => SubscriptionDetailPage(subscriptionId: s.pathParameters['id']!),
      ),
      _full(
        '/subscriptions/:id/edit',
        (s) => SubscriptionFormPage(subscriptionId: s.pathParameters['id']),
      ),
      _full('/savings', (_) => const SavingsPage()),
      _full('/third-party', (_) => const ThirdPartyPage()),
      _full('/third-party/new', (_) => const ThirdPartyFormPage()),
      _full(
        '/third-party/:id',
        (s) => ThirdPartyDetailPage(passId: s.pathParameters['id']!),
      ),
      _full(
        '/third-party/:id/edit',
        (s) => ThirdPartyFormPage(passId: s.pathParameters['id']),
      ),
      _full('/reminders', (_) => const RemindersPage()),
      _full(
        '/reminders/new',
        (s) => ReminderFormPage(
          payment: s.uri.queryParameters['kind'] == 'payment',
        ),
      ),
      _full(
        '/reminders/:id/edit',
        (s) => ReminderFormPage(reminderId: s.pathParameters['id']),
      ),
      _full(
        '/dues/new/:kind',
        (s) => DueFormPage(
          kind: switch (s.pathParameters['kind']) {
            'lent' => DueKind.lent,
            'borrowed' => DueKind.borrowed,
            _ => DueKind.expectedIncome,
          },
          personId: s.uri.queryParameters['person'],
        ),
      ),
      _full(
        '/dues/:id',
        (s) => DueDetailPage(
          dueId: s.pathParameters['id']!,
          action: s.uri.queryParameters['action'],
        ),
      ),
      _full(
        '/dues/:id/edit',
        (s) => DueFormPage(dueId: s.pathParameters['id']),
      ),
      _full('/people', (_) => const PeoplePage()),
      _full('/people/new', (_) => const PersonFormPage()),
      _full(
        '/people/:id',
        (s) => PersonDetailPage(personId: s.pathParameters['id']!),
      ),
      _full(
        '/people/:id/edit',
        (s) => PersonFormPage(personId: s.pathParameters['id']),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
