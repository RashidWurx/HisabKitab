import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/notification_models.dart';
import 'reminder_scheduler.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(),
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
    if (launched != null) _handleTap(launched.payload, launched.action);
    await reschedule();
  }

  /// Many data changes can arrive together; plan once after they settle.
  void requestReschedule() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), reschedule);
  }

  void _handleTap(String payload, String? action) {
    // The router may not be ready on a cold start: wait a moment.
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      final router = _ref.read(routerProvider);
      var route = routeForPayload(payload, action);
      if (payload.startsWith('reminder:')) {
        // A reminder with an amount / category / account opens Add expense
        // pre-filled; otherwise its edit screen.
        final r = await _ref
            .read(reminderRepositoryProvider)
            .get(payload.substring('reminder:'.length));
        if (r != null &&
            (r.amount != null || r.categoryId != null || r.accountId != null)) {
          route = Uri(
            path: '/transaction/new/expense',
            queryParameters: {
              if (r.amount != null) 'amount': '${r.amount}',
              if (r.categoryId != null) 'category': r.categoryId!,
              if (r.accountId != null) 'account': r.accountId!,
            },
          ).toString();
        }
      }
      router.push(route);
    });
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
    return _scheduler.schedule(plan, sound: settings.soundPrefs);
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
