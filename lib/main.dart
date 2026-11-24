import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/data/notification_coordinator.dart';

void main() {
  runApp(const ProviderScope(child: HisaabApp()));
}

class HisaabApp extends ConsumerStatefulWidget {
  const HisaabApp({super.key});

  @override
  ConsumerState<HisaabApp> createState() => _HisaabAppState();
}

class _HisaabAppState extends ConsumerState<HisaabApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensurePaydays();
    // Notifications need the first frame (router, permissions dialog host).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(notificationCoordinatorProvider).start(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensurePaydays();
      ref.read(notificationCoordinatorProvider).requestReschedule();
    }
  }

  /// Rolling payday dues: on start, on resume and when sources change.
  void _ensurePaydays() {
    ref.read(paydayServiceProvider).ensureNextPaydays();
    ref.read(reminderRepositoryProvider).rollForward();
  }

  @override
  Widget build(BuildContext context) {
    // Sources can change schedule, amount, account or status.
    ref.listen(sourcesProvider, (_, _) => _ensurePaydays());
    // Re-plan notifications after any data change (debounced).
    listenForReschedule(ref);
    final mode = ref.watch(
      settingsProvider.select((s) => s.value?.themeMode ?? 'system'),
    );
    return MaterialApp.router(
      title: 'Hisaab',
      debugShowCheckedModeBanner: false,
      // Switching light/dark is instant: no cross-fade across the whole tree.
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
