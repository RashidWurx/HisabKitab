import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/database_provider.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/core/router/app_router.dart';
import 'package:hisaab/core/theme/app_theme.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/settings/data/settings_repository.dart';
import 'package:hisaab/features/thirdparty/data/pass_repository.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('record the money coming back and returning it', (tester) async {
    tester.view.physicalSize = const Size(780, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = PassRepository(db);
    late String id;
    await tester.runAsync(() async {
      await SettingsRepository(db).setBool(SettingKeys.onboardingDone, true);
      final bank = await AccountRepository(db).save(
        const AccountDraft(
          name: 'Bank',
          type: AccountType.bank,
          openingBalance: 0,
          colorValue: 1,
          iconKey: 'bank',
        ),
      );
      final people = PersonRepository(db);
      id = await repo.create(
        PassDraft(
          fromPersonId: await people.save(const PersonDraft(name: 'Ali')),
          forPersonId: await people.save(const PersonDraft(name: 'Bilal')),
          amount: 1000000,
          date: DateTime.now(),
          throughMe: true,
          accountId: bank,
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
    expect(find.text('3rd party money'), findsOneWidget); // Home card
    container.read(routerProvider).push('/third-party/$id');
    await settle();

    for (final step in ['Bilal paid me', 'I paid Ali']) {
      await tester.tap(find.widgetWithText(FilledButton, step));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle();
    }

    await tester.runAsync(() async {
      final v = (await repo.view(id))!;
      expect(v.isOpen, isFalse);
      expect(v.entries, hasLength(4));
    });
    expect(find.text('Record what happened'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  });
}
