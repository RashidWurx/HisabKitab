import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/applock/application/app_lock_controller.dart';
import 'features/applock/presentation/lock_screen.dart';
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
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.inactive:
        lock.onInactive();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.onPaused();
      case AppLifecycleState.resumed:
        lock.onResumed();
        _ensurePaydays();
        ref.read(notificationCoordinatorProvider).requestReschedule();
      case AppLifecycleState.detached:
        break;
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
      // App lock sits above the whole app (including dialogs' routes).
      // Tapping any empty space closes the keyboard (iOS has no back button
      // and its number pad has no "done" key). Buttons and fields still win
      // the tap, so this only fires on blank areas.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
