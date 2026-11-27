import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/database_provider.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/router/app_router.dart';
import 'package:hisaab/core/theme/app_theme.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/reminders/data/reminder_repository.dart';
import 'package:hisaab/features/settings/data/settings_repository.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Mark paid takes the money and shows it in Activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    late String id;
    await tester.runAsync(() async {
      await SettingsRepository(db).setBool(SettingKeys.onboardingDone, true);
      final bank = await AccountRepository(db).save(
        const AccountDraft(
          name: 'Bank',
          type: AccountType.bank,
          openingBalance: 2000000,
          colorValue: 1,
          iconKey: 'bank',
        ),
      );
      id = await ReminderRepository(db).save(
        ReminderDraft(
          title: 'Siblings',
          amount: 500000,
          categoryId: 'cat_exp_rent',
          accountId: bank,
          remindAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await settle();
    container.read(routerProvider).push('/reminders');
    await settle();

    expect(find.text('Unpaid'), findsOneWidget);
    // Nothing on a planned payment can hide it by accident.
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.text('Mark paid'));
    await settle();
    expect(find.text('Balance after: Rs 15,000'), findsOneWidget);

    await tester.tap(find.text('Confirm payment of Rs 5,000'));
    await settle();

    await tester.runAsync(() async {
      final tx = (await db.select(db.transactions).get()).single;
      expect(tx.type, TransactionType.expense);
      expect(tx.amount, 500000);
      expect(tx.note, 'Siblings');
      expect((await ReminderRepository(db).get(id))!.isActive, isFalse);
    });
    expect(find.text('Paid or finished'), findsOneWidget);

    container.read(routerProvider).go('/activity');
    await settle();
    expect(find.textContaining('Siblings'), findsOneWidget);
    expect(find.text('-Rs 5,000'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  });
}
