import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/features/applock/application/app_lock_controller.dart';
import 'package:hisaab/features/applock/data/app_lock_service.dart';
import 'package:hisaab/features/applock/domain/pin_logic.dart';
import 'package:hisaab/features/applock/presentation/lock_screen.dart';

void main() {
  late AppLockService service;

  Future<ProviderContainer> start(
    WidgetTester tester, {
    bool enable = true,
  }) async {
    service = AppLockService(MemoryKv(), iterations: 5);
    if (enable) await service.enable('2580');
    final container = ProviderContainer(
      overrides: [appLockServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('Your money'))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    return container;
  }

  Future<void> type(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('shows the lock screen when the lock is on', (tester) async {
    await start(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
  });

  testWidgets('no lock screen when the lock is off', (tester) async {
    await start(tester, enable: false);
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('Your money'), findsOneWidget);
  });

  testWidgets('wrong PIN is refused, right PIN unlocks', (tester) async {
    final container = await start(tester);
    await type(tester, '1111');
    expect(find.text('Wrong PIN, try again'), findsOneWidget);
    expect(container.read(appLockProvider).locked, isTrue);
    await type(tester, '2580');
    expect(container.read(appLockProvider).locked, isFalse);
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('five wrong PINs lock the pad for a while', (tester) async {
    await start(tester);
    for (var i = 0; i < 5; i++) {
      await type(tester, '1111');
    }
    expect(find.textContaining('Too many tries'), findsOneWidget);
  });

  testWidgets('locks again after going to the background (immediately)',
      (tester) async {
    final container = await start(tester);
    await type(tester, '2580');
    final lock = container.read(appLockProvider.notifier);
    lock.onPaused();
    lock.onResumed();
    await tester.pump();
    expect(container.read(appLockProvider).locked, isTrue);
    expect(find.text('Enter your PIN'), findsOneWidget);
  });

  testWidgets('a 5 minute timeout does not lock on a quick return',
      (tester) async {
    final container = await start(tester);
    await service.setTimeout(LockTimeout.fiveMinutes);
    await tester.runAsync(
      () => container.read(appLockProvider.notifier).setTimeout(LockTimeout.fiveMinutes),
    );
    await type(tester, '2580');
    final lock = container.read(appLockProvider.notifier);
    lock.onPaused();
    lock.onResumed();
    await tester.pump();
    expect(container.read(appLockProvider).locked, isFalse);
  });
}
