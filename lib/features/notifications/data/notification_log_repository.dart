import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/notification_models.dart';

/// The notification log: what was scheduled, and what the user has handled.
/// Rows whose time has passed and that are not handled form the "Missed"
/// inbox (Android does not tell the app when a notification was shown or
/// swiped away while the app was closed).
class NotificationLogRepository {
  NotificationLogRepository(this._db);

  final AppDatabase _db;

  static const keepHandledDays = 30;
  static const maxUnhandled = 200;

  /// Records the new plan. Existing rows keep their handled state.
  /// Future rows that are no longer planned (the due was paid, the reminder
  /// was edited...) are removed; past rows stay for the inbox.
  Future<void> syncPlan(List<PlannedReminder> plan, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    await _db.transaction(() async {
      final keys = <String>{};
      for (final r in plan) {
        keys.add(r.key);
        await _db
            .into(_db.notificationLog)
            .insert(
              NotificationLogCompanion.insert(
                key: r.key,
                notificationId: notificationIdFor(r.key),
                type: r.type.name,
                title: r.title,
                body: r.body,
                payload: r.payload,
                fireAt: r.at,
              ),
              onConflict: DoUpdate(
                (_) => NotificationLogCompanion(
                  title: Value(r.title),
                  body: Value(r.body),
                ),
              ),
            );
      }
      await (_db.delete(_db.notificationLog)..where(
            (l) =>
                l.fireAt.isBiggerThanValue(current) &
                l.isSnooze.equals(false) &
                l.key.isNotIn(keys),
          ))
          .go();
      // Old handled rows go away.
      await (_db.delete(_db.notificationLog)..where(
            (l) =>
                l.handledAt.isNotNull() &
                l.handledAt.isSmallerThanValue(
                  current.subtract(const Duration(days: keepHandledDays)),
                ),
          ))
          .go();
      // Never let the inbox grow without limit: keep the newest 200.
      final unhandled =
          await (_db.select(_db.notificationLog)
                ..where(
                  (l) =>
                      l.handledAt.isNull() &
                      l.fireAt.isSmallerOrEqualValue(current),
                )
                ..orderBy([(l) => OrderingTerm.desc(l.fireAt)]))
              .get();
      if (unhandled.length > maxUnhandled) {
        final drop = unhandled.skip(maxUnhandled).map((r) => r.key).toList();
        await (_db.delete(_db.notificationLog)
              ..where((l) => l.key.isIn(drop)))
            .go();
      }
    });
  }

  /// Snoozed copies that still have to fire.
  Future<List<NotificationLogData>> upcomingSnoozes({DateTime? now}) {
    final current = now ?? DateTime.now();
    return (_db.select(_db.notificationLog)..where(
          (l) =>
              l.isSnooze.equals(true) &
              l.handledAt.isNull() &
              l.fireAt.isBiggerThanValue(current),
        ))
        .get();
  }

  /// All rows the user has not handled (the screen filters by time).
  Stream<List<NotificationLogData>> watchUnhandled() =>
      (_db.select(_db.notificationLog)
            ..where((l) => l.handledAt.isNull())
            ..orderBy([(l) => OrderingTerm.desc(l.fireAt)]))
          .watch();

  /// Marks the row as handled. [notificationId] is what Android reports when
  /// a notification is tapped.
  Future<void> handleByKey(String key, {DateTime? now}) =>
      (_db.update(_db.notificationLog)..where((l) => l.key.equals(key))).write(
        NotificationLogCompanion(handledAt: Value(now ?? DateTime.now())),
      );

  Future<void> handleById(int notificationId, {DateTime? now}) =>
      (_db.update(_db.notificationLog)
            ..where(
              (l) =>
                  l.notificationId.equals(notificationId) &
                  l.handledAt.isNull(),
            ))
          .write(
            NotificationLogCompanion(handledAt: Value(now ?? DateTime.now())),
          );

  Future<void> handleAllMissed({DateTime? now}) {
    final current = now ?? DateTime.now();
    return (_db.update(_db.notificationLog)..where(
          (l) => l.handledAt.isNull() & l.fireAt.isSmallerOrEqualValue(current),
        ))
        .write(NotificationLogCompanion(handledAt: Value(current)));
  }

  /// Handles every unhandled past row about the same item (for example all
  /// the reminders of one due), used when the item is dealt with.
  Future<void> handleByPayload(String payload, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return (_db.update(_db.notificationLog)..where(
          (l) =>
              l.payload.equals(payload) &
              l.handledAt.isNull() &
              l.fireAt.isSmallerOrEqualValue(current),
        ))
        .write(NotificationLogCompanion(handledAt: Value(current)));
  }

  /// "Remind me later": hands the old row off and creates a snooze copy.
  Future<DateTime> snooze(
    NotificationLogData row, {
    Duration by = const Duration(hours: 1),
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final at = current.add(by);
    final key = 'snooze|${row.payload}@${at.millisecondsSinceEpoch}';
    await _db.transaction(() async {
      await handleByKey(row.key, now: current);
      await _db
          .into(_db.notificationLog)
          .insertOnConflictUpdate(
            NotificationLogCompanion.insert(
              key: key,
              notificationId: notificationIdFor(key),
              type: row.type,
              title: row.title,
              body: row.body,
              payload: row.payload,
              fireAt: at,
              isSnooze: const Value(true),
            ),
          );
    });
    return at;
  }

  /// A one-off notification that is not part of the plan (the test button).
  Future<void> addOneOff({
    required String title,
    required String body,
    required String payload,
    required DateTime at,
  }) {
    final key = 'once|$payload@${at.millisecondsSinceEpoch}';
    return _db
        .into(_db.notificationLog)
        .insertOnConflictUpdate(
          NotificationLogCompanion.insert(
            key: key,
            notificationId: notificationIdFor(key),
            type: NotificationType.custom.name,
            title: title,
            body: body,
            payload: payload,
            fireAt: at,
            isSnooze: const Value(true),
          ),
        );
  }

  /// Past rows about things that no longer need attention (a settled due,
  /// a deleted reminder) are closed automatically.
  Future<void> resolveGone({
    required Set<String> openDueIds,
    required Set<String> subscriptionIds,
    required Set<String> reminderIds,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final rows =
        await (_db.select(_db.notificationLog)..where(
              (l) =>
                  l.handledAt.isNull() &
                  l.fireAt.isSmallerOrEqualValue(current),
            ))
            .get();
    for (final r in rows) {
      final p = r.payload;
      final gone =
          (p.startsWith('due:') && !openDueIds.contains(p.substring(4))) ||
          (p.startsWith('sub:') && !subscriptionIds.contains(p.substring(4))) ||
          (p.startsWith('reminder:') &&
              !reminderIds.contains(p.substring(9))) ||
          (p.startsWith('pay:') && !reminderIds.contains(p.substring(4)));
      if (gone) await handleByKey(r.key, now: current);
    }
  }
}
