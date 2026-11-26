import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/seed.dart';
import '../../notifications/domain/notification_models.dart';

/// Keys stored in the `app_settings` table.
abstract final class SettingKeys {
  static const askSourceEachExpense = 'ask_source_each_expense';
  static const onboardingDone = 'onboarding_done';
  static const monthStartDay = 'month_start_day';
  static const themeMode = 'theme_mode'; // system | light | dark
  static const homePeriod = 'home_period'; // see PeriodSelection.encode
  static const backupAnchor = 'notif.backup.anchor'; // epoch millis
  static const notificationsAsked = 'notif.permission_asked';
}

/// Typed view over the settings table.
class AppSettingsData {
  const AppSettingsData(this._values);

  final Map<String, String> _values;

  /// Raw stored value for [key] (null when never set).
  String? raw(String key) => _values[key];

  NotificationPrefs get notificationPrefs => NotificationPrefs.fromRaw(raw);
  SoundPrefs get soundPrefs => SoundPrefs.fromRaw(raw);

  bool get askSourceEachExpense =>
      (_values[SettingKeys.askSourceEachExpense] ?? '1') == '1';
  bool get onboardingDone => _values[SettingKeys.onboardingDone] == '1';
  int get monthStartDay =>
      int.tryParse(_values[SettingKeys.monthStartDay] ?? '') ?? 1;
  String get themeMode => _values[SettingKeys.themeMode] ?? 'system';
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<AppSettingsData> watch() => _db.select(_db.appSettings).watch().map(
    (rows) => AppSettingsData({for (final r in rows) r.key: r.value}),
  );

  Future<void> set(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');

  /// Danger zone: wipes everything and re-seeds the built-in data.
  Future<void> deleteAllData() async {
    await _db.transaction(() async {
      // Rows reference each other in a loop (accounts <-> sources), so check
      // foreign keys only at commit time.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in <TableInfo<Table, Object?>>[
        _db.passEntries,
        _db.passThroughs,
        _db.dueEvents,
        _db.transactionAllocations,
        _db.transactions,
        _db.dues,
        _db.subscriptions,
        _db.customReminders,
        _db.accountOpeningAllocations,
        _db.categories,
        _db.people,
        _db.incomeSources,
        _db.accounts,
        _db.appSettings,
      ]) {
        await _db.delete(table).go();
      }
    });
    await seedDatabase(_db);
  }
}
