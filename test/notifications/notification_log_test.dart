import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/features/notifications/data/notification_log_repository.dart';
import 'package:hisaab/features/notifications/domain/notification_models.dart';

PlannedReminder reminder(String payload, DateTime at) => PlannedReminder(
  at: at,
  type: NotificationType.owed,
  title: 'Title $payload',
  body: 'Body',
  payload: payload,
);

void main() {
  late AppDatabase db;
  late NotificationLogRepository repo;
  final now = DateTime(2026, 11, 25, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = NotificationLogRepository(db);
  });
  tearDown(() => db.close());

  Future<List<NotificationLogData>> missed() async =>
      (await db.select(db.notificationLog).get())
          .where((r) => r.handledAt == null && !r.fireAt.isAfter(now))
          .toList();

  test('notification ids are stable and differ per notification', () {
    final a = reminder('due:1', now);
    final b = reminder('due:2', now);
    expect(notificationIdFor(a.key), notificationIdFor(a.key));
    expect(notificationIdFor(a.key), isNot(notificationIdFor(b.key)));
    expect(notificationIdFor(a.key), greaterThanOrEqualTo(0));
  });

  test('past planned items become missed once their time has passed', () async {
    final past = reminder('due:1', now.subtract(const Duration(hours: 2)));
    final future = reminder('due:2', now.add(const Duration(days: 1)));
    await repo.syncPlan([past, future], now: now);
    expect((await missed()).map((r) => r.payload), ['due:1']);
  });

  test('a re-plan keeps past rows and drops future ones no longer planned',
      () async {
    final past = reminder('due:1', now.subtract(const Duration(hours: 2)));
    final future = reminder('due:2', now.add(const Duration(days: 1)));
    await repo.syncPlan([past, future], now: now);
    // The due 2 was paid, and the plan no longer has the past item either.
    await repo.syncPlan([], now: now);
    final rows = await db.select(db.notificationLog).get();
    expect(rows.map((r) => r.payload), ['due:1']);
  });

  test('handled rows leave the inbox and stay handled after a re-plan',
      () async {
    final past = reminder('due:1', now.subtract(const Duration(hours: 2)));
    await repo.syncPlan([past], now: now);
    final row = (await db.select(db.notificationLog).get()).single;
    await repo.handleById(row.notificationId, now: now);
    await repo.syncPlan([past], now: now);
    expect(await missed(), isEmpty);
  });

  test('snooze hides the old row and schedules a copy an hour later',
      () async {
    final past = reminder('due:1', now.subtract(const Duration(hours: 2)));
    await repo.syncPlan([past], now: now);
    final row = (await db.select(db.notificationLog).get()).single;
    final at = await repo.snooze(row, now: now);
    expect(at, now.add(const Duration(hours: 1)));
    expect(await missed(), isEmpty);
    final snoozes = await repo.upcomingSnoozes(now: now);
    expect(snoozes.single.payload, 'due:1');
    // A re-plan must not delete the snooze.
    await repo.syncPlan([], now: now);
    expect(await repo.upcomingSnoozes(now: now), hasLength(1));
  });

  test('rows about settled dues or deleted items close automatically',
      () async {
    final t = now.subtract(const Duration(hours: 1));
    await repo.syncPlan([
      reminder('due:open', t),
      reminder('due:paid', t),
      reminder('sub:gone', t),
      reminder('reminder:live', t),
    ], now: now);
    await repo.resolveGone(
      openDueIds: {'open'},
      subscriptionIds: {},
      reminderIds: {'live'},
      now: now,
    );
    expect((await missed()).map((r) => r.payload).toSet(), {
      'due:open',
      'reminder:live',
    });
  });

  test('the inbox is capped at 200 unhandled rows', () async {
    final plan = [
      for (var i = 0; i < 230; i++)
        reminder('due:$i', now.subtract(Duration(minutes: i + 1))),
    ];
    await repo.syncPlan(plan, now: now);
    expect(await missed(), hasLength(NotificationLogRepository.maxUnhandled));
  });
}