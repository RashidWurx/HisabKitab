import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/accounts/presentation/account_detail_page.dart';
import '../../features/accounts/presentation/account_form_page.dart';
import '../../features/accounts/presentation/accounts_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/categories/presentation/category_form_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/more/presentation/more_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/placeholder_page.dart';
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
  ref.listen(settingsProvider, (_, _) => refresh.value++);
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
                builder: (_, _) => const PlaceholderPage(title: 'Dues'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/subscriptions',
                builder: (_, _) => const PlaceholderPage(title: 'Subscriptions'),
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
      _full('/accounts/new', (_) => const AccountFormPage()),
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
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
