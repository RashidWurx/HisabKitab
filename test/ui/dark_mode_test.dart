import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/database_provider.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/theme/app_theme.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/applock/application/app_lock_controller.dart';
import 'package:hisaab/features/applock/data/app_lock_service.dart';
import 'package:hisaab/features/accounts/presentation/accounts_page.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/dues/presentation/dues_page.dart';
import 'package:hisaab/features/home/presentation/home_page.dart';
import 'package:hisaab/features/more/presentation/more_page.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/thirdparty/data/pass_repository.dart';
import 'package:hisaab/features/thirdparty/presentation/third_party_form_page.dart';
import 'package:hisaab/features/thirdparty/presentation/third_party_page.dart';
import 'package:hisaab/features/reminders/data/reminder_repository.dart';
import 'package:hisaab/features/reminders/presentation/reminders_page.dart';
import 'package:hisaab/features/savings/presentation/savings_page.dart';
import 'package:hisaab/features/settings/presentation/settings_page.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';
import 'package:hisaab/features/transactions/presentation/activity_page.dart';
import 'package:hisaab/features/transactions/presentation/transaction_form_page.dart';
import 'package:material_ui/material_ui.dart';

/// Renders real screens in dark mode with data in them.
/// - The theme must be pure black and white (no navy tint).
/// - Text must be readable against what is behind it.
/// Run with `--dart-define=SHOTS=<folder>` to also save a picture of each.
const shots = String.fromEnvironment('SHOTS');

void main() {
  test('dark theme surfaces and text are neutral black and white', () {
    final s = AppTheme.dark().colorScheme;
    expect(s.surface, Colors.black);
    expect(s.onSurface, Colors.white);
    expect(s.primary, Colors.white);
    for (final c in [
      s.surface,
      s.onSurface,
      s.onSurfaceVariant,
      s.primary,
      s.onPrimary,
      s.secondary,
      s.secondaryContainer,
      s.surfaceContainerLowest,
      s.surfaceContainerLow,
      s.surfaceContainer,
      s.surfaceContainerHigh,
      s.outline,
      s.outlineVariant,
    ]) {
      expect(c.r, c.g, reason: '$c has a tint');
      expect(c.g, c.b, reason: '$c has a tint');
    }
  });

  setUpAll(() async {
    // Real fonts, so the saved pictures are readable.
    final root = Platform.environment['FLUTTER_ROOT']!;
    final dir = '$root/bin/cache/artifacts/material_fonts';
    Future<ByteData> read(String f) async =>
        ByteData.sublistView(await File('$dir/$f').readAsBytes());
    for (final family in ['Roboto', 'FlutterTest', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(read('roboto-regular.ttf'))
        ..addFont(read('roboto-bold.ttf'));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(read('materialicons-regular.otf'));
    await icons.load();
  });

  final screens = <String, Widget Function(String account)>{
    'home': (_) => const HomePage(),
    'activity': (_) => const ActivityPage(),
    'dues': (_) => const DuesPage(),
    'subscriptions': (_) => const SubscriptionsPage(),
    'more': (_) => const MorePage(),
    'settings': (_) => const SettingsPage(),
    'accounts': (_) => const AccountsPage(),
    'savings': (_) => const SavingsPage(),
    'reminders': (_) => const RemindersPage(),
    'plan_payment': (_) => const ReminderFormPage(payment: true),
    'to_pay': (_) => const DuesPage(initialTab: 1),
    'third_party': (_) => const ThirdPartyPage(),
    'third_party_form': (_) => const ThirdPartyFormPage(),
    'add_expense': (_) =>
        const TransactionFormPage(type: TransactionType.expense),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} is readable in dark mode', (tester) async {
      tester.view.physicalSize = Size(780, entry.key == 'home' ? 4400 : 1700);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      late String account;
      await tester.runAsync(() async => account = await _seed(db));
      final boundary = GlobalKey();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => entry.value(account)),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appLockServiceProvider.overrideWithValue(
              AppLockService(MemoryKv()),
            ),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
              routerConfig: router,
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);

      if (shots.isNotEmpty) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$shots/${entry.key}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      } else {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }

      // Tear down so database streams and timers stop.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(db.close);
    });
  }
}

Future<String> _seed(AppDatabase db) async {
  const rs = 100;
  final now = DateTime.now();
  final job = await SourceRepository(db).save(
    const SourceDraft(name: 'Job', colorValue: 0xFF2A4E76, iconKey: 'work'),
  );
  final accounts = AccountRepository(db);
  final bank = await accounts.save(
    const AccountDraft(
      name: 'Meezan',
      type: AccountType.bank,
      openingBalance: 50000 * rs,
      colorValue: 0xFF112E4E,
      iconKey: 'bank',
    ),
  );
  await accounts.save(
    const AccountDraft(
      name: 'Savings',
      type: AccountType.savings,
      openingBalance: 20000 * rs,
      goalAmount: 100000 * rs,
      colorValue: 0xFF112E4E,
      iconKey: 'savings',
    ),
  );
  final txs = TransactionRepository(db);
  await txs.save(
    TransactionInput(
      type: TransactionType.income,
      amount: 40000 * rs,
      accountId: bank,
      date: now,
      allocations: [AllocationInput(job, 40000 * rs)],
    ),
  );
  await txs.save(
    TransactionInput(
      type: TransactionType.expense,
      amount: 12000 * rs,
      accountId: bank,
      categoryId: 'cat_exp_rent',
      date: now,
      allocations: [AllocationInput(job, 12000 * rs)],
    ),
  );
  await DueRepository(db).create(
    DueDraft(
      title: 'Salary',
      kind: DueKind.expectedIncome,
      sourceId: job,
      totalAmount: 30000 * rs,
      accountId: bank,
      dueDate: now.add(const Duration(days: 3)),
    ),
  );
  await ReminderRepository(db).save(
    ReminderDraft(
      title: 'Siblings',
      amount: 5000 * rs,
      accountId: bank,
      remindAt: now.subtract(const Duration(days: 1)),
    ),
  );
  final people = PersonRepository(db);
  await PassRepository(db).create(
    PassDraft(
      fromPersonId: await people.save(const PersonDraft(name: 'Ali')),
      forPersonId: await people.save(const PersonDraft(name: 'Bilal')),
      amount: 10000 * rs,
      date: now,
      throughMe: true,
      accountId: bank,
      handedOver: false,
      collectBy: now.add(const Duration(days: 2)),
      returnBy: now.add(const Duration(days: 4)),
    ),
  );
  return bank;
}
