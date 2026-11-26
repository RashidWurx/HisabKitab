import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/database_provider.dart';
import 'package:hisaab/core/utils/period.dart';
import 'package:hisaab/features/home/presentation/home_providers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A fresh container = the app opened again on the same data.
  Future<PeriodSelection> openApp([
    void Function(PeriodNotifier notifier)? act,
  ]) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    final sub = container.listen(periodSelectionProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    act?.call(container.read(periodSelectionProvider.notifier));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final result = sub.read();
    container.dispose();
    return result;
  }

  test('a new install starts on This month', () async {
    expect((await openApp()).kind, PeriodKind.thisMonth);
  });

  test('the chosen period survives closing the app', () async {
    await openApp((n) => n.selectPreset(PeriodKind.allTime));
    expect((await openApp()).kind, PeriodKind.allTime);

    await openApp((n) => n.selectPreset(PeriodKind.thisYear));
    expect((await openApp()).kind, PeriodKind.thisYear);
  });

  test('a custom range survives closing the app', () async {
    await openApp(
      (n) => n.selectCustom(DateTime(2026, 11, 3), DateTime(2026, 11, 20)),
    );
    final again = await openApp();

    expect(again.kind, isNull);
    expect(again.custom!.start, DateTime(2026, 11, 3));
    expect(again.custom!.end, DateTime(2026, 11, 21));
  });

  test('a damaged stored value falls back to This month', () {
    expect(PeriodSelection.decode('custom:x:1').kind, PeriodKind.thisMonth);
    expect(PeriodSelection.decode('nonsense').kind, PeriodKind.thisMonth);
  });
}
