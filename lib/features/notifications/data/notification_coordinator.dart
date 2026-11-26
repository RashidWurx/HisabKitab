import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/notification_models.dart';
import 'notification_log_repository.dart';
import 'reminder_scheduler.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(),
);

final notificationLogRepositoryProvider = Provider<NotificationLogRepository>(
  (ref) => NotificationLogRepository(ref.watch(databaseProvider)),
);

final notificationCoordinatorProvider = Provider<NotificationCoordinator>(
  (ref) => NotificationCoordinator(ref),
);

/// Where a notification should take the user.
String routeForPayload(String payload, String? action) {
  final parts = payload.split(':');
  final kind = parts.first;
  final id = parts.length > 1 ? parts.sublist(1).join(':') : '';
  switch (kind) {
    case 'due':
      final query = (action == 'receive' || action == 'extend')
          ? '?action=$action'
          : '';
      return '/dues/$id$query';
    case 'sub':
      return '/subscriptions/$id';
    case 'reminder':
    case 'pay':
      return '/reminders/$id/edit';
    case 'backup':
      return '/backup';
    case 'test':
      return '/settings/notifications';
    default:
      return '/home';
  }
}

/// Keeps the phone's scheduled notifications in sync with the data.
/// Re-plans on app start, on resume and after any data change.
class NotificationCoordinator {
  NotificationCoordinator(this._ref);

  final Ref _ref;
  Timer? _debounce;
  bool _started = false;

  ReminderScheduler get _scheduler => _ref.read(reminderSchedulerProvider);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _scheduler.init(onTap: _handleTap);
    final launched = await _scheduler.launchedBy();
    if (launched != null) {
      _handleTap(launched.payload, launched.action, launched.id);
    }
    await reschedule();
  }

  /// Many data changes can arrive together; plan once after they settle.
  void requestReschedule() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), reschedule);
  }

  Future<void> _handleTap(String payload, String? action, int? id) async {
    final log = _ref.read(notificationLogRepositoryProvider);
    if (action == 'snooze' && id != null) {
      final rows = await (_ref.read(databaseProvider).select(_ref.read(databaseProvider).notificationLog)
            ..where((l) => l.notificationId.equals(id)))
          .get();
      if (rows.isNotEmpty) await snooze(rows.first);
      return; // stay where the user was
    }
    if (id != null) await log.handleById(id);
    if (action == 'done') return;
    // The router may not be ready on a cold start: wait a moment.
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      final route = await resolveRoute(payload, action);
      _ref.read(routerProvider).push(route);
    });
  }

  /// The screen a notification leads to. A planned payment, or a reminder with
  /// a category or account, opens Add expense pre-filled; otherwise its edit
  /// screen.
  Future<String> resolveRoute(String payload, String? action) async {
    var route = routeForPayload(payload, action);
    final isPay = payload.startsWith('pay:');
    if (isPay || payload.startsWith('reminder:')) {
      final r = await _ref
          .read(reminderRepositoryProvider)
          .get(payload.substring(payload.indexOf(':') + 1));
      if (isPay) {
        // Gone, switched off, or already moved on to a later date: it has
        // been dealt with, so show the list instead of a second payment.
        return r != null && r.isUnpaid(DateTime.now())
            ? expenseRouteFor(r)
            : '/reminders';
      }
      if (r != null && (r.categoryId != null || r.accountId != null)) {
        route = expenseRouteFor(r);
      }
    }
    return route;
  }

  /// The settings page's test: goes through the real plan + inbox path.
  Future<void> scheduleTest() async {
    await _ref.read(notificationLogRepositoryProvider).addOneOff(
      title: 'Hisaab',
      body: 'Scheduled reminders work on this phone.',
      payload: 'test',
      at: DateTime.now().add(const Duration(minutes: 1)),
    );
    await reschedule();
  }

  /// Remind me again in an hour.
  Future<DateTime> snooze(NotificationLogData row, {Duration by = const Duration(hours: 1)}) async {
    final at = await _ref.read(notificationLogRepositoryProvider).snooze(row, by: by);
    await reschedule();
    return at;
  }

  /// Cancel everything, then schedule the nearest 60 upcoming reminders.
  Future<int> reschedule() async {
    if (!_scheduler.isReady) return 0;
    final db = _ref;
    final settings = await db.read(settingsProvider.future);
    var anchor = settings.raw(SettingKeys.backupAnchor);
    if (anchor == null) {
      anchor = '${DateTime.now().millisecondsSinceEpoch}';
      await db.read(settingsRepositoryProvider).set(SettingKeys.backupAnchor, anchor);
    }
    final dues = await db.read(dueRepositoryProvider).watchViews().first;
    final subs = await db.read(subscriptionRepositoryProvider).watchAll().first;
    final reminders = await db.read(reminderRepositoryProvider).watchAll().first;
    final people = await db.read(peopleProvider.future);
    final sources = await db.read(sourcesProvider.future);
    final accounts = await db.read(accountsProvider.future);
    final plan = planReminders(
      PlanInput(
        now: DateTime.now(),
        prefs: settings.notificationPrefs,
        dues: dues,
        people: {for (final p in people) p.id: p},
        sources: {for (final s in sources) s.id: s},
        accounts: {for (final a in accounts) a.id: a},
        subscriptions: subs,
        reminders: reminders,
        backupAnchor: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(anchor) ?? DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    final log = db.read(notificationLogRepositoryProvider);
    final snoozes = await log.upcomingSnoozes();
    final all = [
      ...plan,
      for (final s in snoozes)
        PlannedReminder(
          at: s.fireAt,
          type: NotificationType.values.firstWhere(
            (t) => t.name == s.type,
            orElse: () => NotificationType.custom,
          ),
          title: s.title,
          body: s.body,
          payload: s.payload,
          dueActions: s.payload.startsWith('due:'),
          keyOverride: s.key,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final limited = all.take(maxScheduled).toList();
    await log.syncPlan(limited);
    await log.resolveGone(
      openDueIds: {for (final d in dues) if (d.isOpen) d.due.id},
      subscriptionIds: {for (final s in subs) s.id},
      reminderIds: {for (final r in reminders) r.id},
    );
    return _scheduler.schedule(limited, sound: settings.soundPrefs);
  }

  void dispose() => _debounce?.cancel();
}

/// Everything that can change what should be scheduled.
void listenForReschedule(WidgetRef ref) {
  final coordinator = ref.read(notificationCoordinatorProvider);
  void again(Object? previous, Object? next) => coordinator.requestReschedule();
  ref.listen(dueViewsProvider, again);
  ref.listen(subscriptionsProvider, again);
  ref.listen(remindersProvider, again);
  ref.listen(sourcesProvider, again);
  ref.listen(accountsProvider, again);
  ref.listen(peopleProvider, again);
  ref.listen(settingsProvider, again);
}
