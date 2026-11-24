import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/placeholder_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Bottom-nav tabs. Each is a StatefulShellBranch so tab state is kept.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const PlaceholderPage(title: 'Home'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/activity',
              builder: (_, _) => const PlaceholderPage(title: 'Activity'),
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
            GoRoute(
              path: '/more',
              builder: (_, _) => const PlaceholderPage(title: 'More'),
            ),
          ],
        ),
      ],
    ),
  ],
);
