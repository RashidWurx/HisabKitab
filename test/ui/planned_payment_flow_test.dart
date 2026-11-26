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
  testWidgets('Paid opens the filled expense and saving it takes the money', (
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
    await tester.tap(find.text('Paid'));
    await settle();
    expect(find.text('Add expense'), findsOneWidget);

    await tester.tap(find.text('Save expense'));
    await settle();

    await tester.runAsync(() async {
      final tx = (await db.select(db.transactions).get()).single;
      expect(tx.type, TransactionType.expense);
      expect(tx.amount, 500000);
      expect(tx.note, 'Siblings');
      expect((await ReminderRepository(db).get(id))!.isActive, isFalse);
    });
    expect(find.text('Done'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  });
}
