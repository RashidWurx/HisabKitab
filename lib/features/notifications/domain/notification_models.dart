import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/utils/money.dart';
import '../../dues/domain/due_models.dart';
import '../../reminders/data/reminder_repository.dart';

/// The 8 kinds of notification, each with its own settings.
enum NotificationType {
  payday,
  expectedFollowUp,
  owe,
  owed,
  subscription,
  custom,
  overdue,
  backup,
}

const notificationTypeLabels = {
  NotificationType.payday: 'Paydays',
  NotificationType.expectedFollowUp: 'Expected cash in follow-ups',
  NotificationType.owe: 'Money you owe',
  NotificationType.owed: 'Money owed to you',
  NotificationType.subscription: 'Subscriptions',
  NotificationType.custom: 'Custom reminders',
  NotificationType.overdue: 'Overdue nudges',
  NotificationType.backup: 'Backup reminder',
};

/// Settings of one notification type.
class TypePrefs {
  const TypePrefs({
    this.enabled = true,
    this.minutes = 9 * 60,
    this.days = 1,
  });

  final bool enabled;

  /// Default time of day, in minutes after midnight (9:00 = 540).
  final int minutes;

  /// Days before the date (dues, paydays, subscriptions); repeat interval in
  /// days for overdue nudges; days without a backup for the backup reminder.
  final int days;

  TypePrefs copyWith({bool? enabled, int? minutes, int? days}) => TypePrefs(
    enabled: enabled ?? this.enabled,
    minutes: minutes ?? this.minutes,
    days: days ?? this.days,
  );
}

/// Whether a type uses the "days" field, and what it means.
String? daysLabel(NotificationType t) => switch (t) {
  NotificationType.payday ||
  NotificationType.expectedFollowUp ||
  NotificationType.owe ||
  NotificationType.owed ||
  NotificationType.subscription => 'Days before (also reminds on the day)',
  NotificationType.overdue => 'Repeat every (days)',
  NotificationType.backup => 'No backup for (days)',
  NotificationType.custom => null,
};

class NotificationPrefs {
  const NotificationPrefs(this._byType);

  final Map<NotificationType, TypePrefs> _byType;

  static const _defaults = {
    NotificationType.payday: TypePrefs(),
    NotificationType.expectedFollowUp: TypePrefs(),
    NotificationType.owe: TypePrefs(),
    NotificationType.owed: TypePrefs(),
    NotificationType.subscription: TypePrefs(),
    NotificationType.custom: TypePrefs(),
    NotificationType.overdue: TypePrefs(),
    NotificationType.backup: TypePrefs(days: 7),
  };

  static const defaults = NotificationPrefs(_defaults);

  TypePrefs of(NotificationType t) => _byType[t] ?? _defaults[t]!;

  static String keyOf(NotificationType t, String field) => 'notif.${t.name}.$field';

  /// Reads prefs from raw settings values (see `app_settings`).
  factory NotificationPrefs.fromRaw(String? Function(String key) get) {
    final map = <NotificationType, TypePrefs>{};
    for (final t in NotificationType.values) {
      final d = _defaults[t]!;
      map[t] = TypePrefs(
        enabled: (get(keyOf(t, 'enabled')) ?? (d.enabled ? '1' : '0')) == '1',
        minutes: int.tryParse(get(keyOf(t, 'minutes')) ?? '') ?? d.minutes,
        days: int.tryParse(get(keyOf(t, 'days')) ?? '') ?? d.days,
      );
    }
    return NotificationPrefs(map);
  }
}

/// One notification the app wants the phone to show.
class PlannedReminder {
  const PlannedReminder({
    required this.at,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    this.dueActions = false,
  });

  final DateTime at;
  final NotificationType type;
  final String title;
  final String body;

  /// Where tapping goes: `due:<id>`, `sub:<id>`, `reminder:<id>`, `backup`.
  final String payload;

  /// Due and payday notifications get "Received" / "Extend" buttons.
  final bool dueActions;
}

/// iOS allows 64 pending notifications; we schedule the nearest 60 on
/// every platform.
const maxScheduled = 60;

class PlanInput {
  const PlanInput({
    required this.now,
    required this.prefs,
    this.dues = const [],
    this.people = const {},
    this.sources = const {},
    this.accounts = const {},
    this.subscriptions = const [],
    this.reminders = const [],
    this.backupAnchor,
  });

  final DateTime now;
  final NotificationPrefs prefs;
  final List<DueView> dues;
  final Map<String, PeopleData> people;
  final Map<String, IncomeSource> sources;
  final Map<String, Account> accounts;
  final List<Subscription> subscriptions;
  final List<CustomReminder> reminders;

  /// When the last backup happened (or when the app was first used).
  final DateTime? backupAnchor;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _atMinutes(DateTime day, int minutes) =>
    DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

String _when(DateTime dueDate, DateTime notifyAt) {
  final days = _day(dueDate).difference(_day(notifyAt)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'tomorrow';
  return 'on ${_shortDate(dueDate)}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Decides which notifications to show, soonest first, at most
/// [maxScheduled]. Pure function: no plugin, no database.
List<PlannedReminder> planReminders(PlanInput input) {
  final now = input.now;
  final out = <PlannedReminder>[];

  void add(PlannedReminder r) {
    if (r.at.isAfter(now)) out.add(r);
  }

  // ---- dues and paydays ----------------------------------------------------
  for (final v in input.dues) {
    if (!v.isOpen) continue;
    final due = v.due;
    final person = input.people[due.personId]?.name;
    final source = input.sources[due.sourceId];
    final account = input.accounts[due.accountId]?.name;
    final isPayday = due.kind == DueKind.expectedIncome && due.periodKey != null;
    final type = switch (due.kind) {
      DueKind.borrowed => NotificationType.owe,
      DueKind.lent => NotificationType.owed,
      DueKind.expectedIncome =>
        isPayday ? NotificationType.payday : NotificationType.expectedFollowUp,
    };
    final skipPayday =
        isPayday && source != null && source.status == ActiveStatus.inactive;

    String body(DateTime notifyAt) {
      final amount = Money.format(v.remaining);
      final when = _when(due.currentDueDate, notifyAt);
      switch (type) {
        case NotificationType.owed:
          return '${person ?? 'Someone'} owes you $amount. Due $when.';
        case NotificationType.owe:
          return 'You owe ${person ?? 'someone'} $amount. Due $when.';
        case NotificationType.payday:
          return '${source?.name ?? 'Income'} ${due.title.contains('salary') ? 'salary' : 'pay'} expected $when${account == null ? '' : ' in $account'}. Received?';
        default:
          return '${due.title}: $amount expected $when. Received?';
      }
    }

    final main = input.prefs.of(type);
    if (main.enabled && !skipPayday) {
      void plan(DateTime at) => add(
        PlannedReminder(
          at: at,
          type: type,
          title: 'Hisaab',
          body: body(at),
          payload: 'due:${due.id}',
          dueActions: true,
        ),
      );
      if (due.reminderAt != null) {
        // Per-item override: its own date and time, optionally repeating.
        var at = due.reminderAt!;
        plan(at);
        final every = due.reminderRepeatDays;
        if (every != null && every > 0) {
          for (var i = 0; i < 4; i++) {
            at = DateTime(
              at.year,
              at.month,
              at.day + every,
              at.hour,
              at.minute,
            );
            plan(at);
          }
        }
      } else {
        final dueDay = _day(due.currentDueDate);
        plan(_atMinutes(dueDay, main.minutes));
        if (main.days > 0) {
          plan(
            _atMinutes(
              DateTime(dueDay.year, dueDay.month, dueDay.day - main.days),
              main.minutes,
            ),
          );
        }
      }
    }

    // Overdue nudges: from the day after the due date, every N days.
    final nudge = input.prefs.of(NotificationType.overdue);
    if (nudge.enabled && !skipPayday) {
      final every = nudge.days < 1 ? 1 : nudge.days;
      var day = DateTime(
        _day(due.currentDueDate).year,
        _day(due.currentDueDate).month,
        _day(due.currentDueDate).day + 1,
      );
      var guard = 0;
      while (!_atMinutes(day, nudge.minutes).isAfter(now) && guard++ < 4000) {
        day = DateTime(day.year, day.month, day.day + every);
      }
      for (var i = 0; i < 3; i++) {
        final at = _atMinutes(
          DateTime(day.year, day.month, day.day + i * every),
          nudge.minutes,
        );
        final late = _day(at).difference(_day(due.originalDueDate)).inDays;
        add(
          PlannedReminder(
            at: at,
            type: NotificationType.overdue,
            title: 'Hisaab',
            body:
                '${due.title} is overdue (late by $late days). ${Money.format(v.remaining)} remaining.',
            payload: 'due:${due.id}',
            dueActions: true,
          ),
        );
      }
    }
  }

  // ---- subscriptions ---------------------------------------------------------
  final subPrefs = input.prefs.of(NotificationType.subscription);
  if (subPrefs.enabled) {
    for (final s in input.subscriptions) {
      if (s.status != SubscriptionStatus.active) continue;
      final account = input.accounts[s.accountId]?.name;
      final dueDay = _day(s.nextDueDate);
      final before = s.reminderDaysBefore ?? subPrefs.days;
      String text(DateTime at) =>
          '${s.name} renews ${_when(dueDay, at)}: ${Money.format(s.amount)}${account == null ? '' : ' from $account'}.';
      void plan(DateTime at) => add(
        PlannedReminder(
          at: at,
          type: NotificationType.subscription,
          title: 'Hisaab',
          body: text(at),
          payload: 'sub:${s.id}',
        ),
      );
      plan(_atMinutes(dueDay, subPrefs.minutes));
      if (before > 0) {
        plan(
          _atMinutes(
            DateTime(dueDay.year, dueDay.month, dueDay.day - before),
            subPrefs.minutes,
          ),
        );
      }
    }
  }

  // ---- custom reminders -------------------------------------------------------
  if (input.prefs.of(NotificationType.custom).enabled) {
    for (final r in input.reminders) {
      if (!r.isActive) continue;
      var at = r.remindAt;
      for (var i = 0; i < 3; i++) {
        add(
          PlannedReminder(
            at: at,
            type: NotificationType.custom,
            title: r.title,
            body: r.amount == null
                ? 'Reminder'
                : 'Reminder · ${Money.format(r.amount!)}',
            payload: 'reminder:${r.id}',
          ),
        );
        final next = nextReminderTime(
          at: at,
          repeat: r.repeat,
          everyDays: r.repeatEveryDays,
          anchorDay: r.remindAt.day,
        );
        if (next == null) break;
        at = next;
      }
    }
  }

  // ---- backup ---------------------------------------------------------------
  final backup = input.prefs.of(NotificationType.backup);
  if (backup.enabled && input.backupAnchor != null) {
    final every = backup.days < 1 ? 1 : backup.days;
    var day = _day(input.backupAnchor!);
    day = DateTime(day.year, day.month, day.day + every);
    var guard = 0;
    while (!_atMinutes(day, backup.minutes).isAfter(now) && guard++ < 4000) {
      day = DateTime(day.year, day.month, day.day + every);
    }
    add(
      PlannedReminder(
        at: _atMinutes(day, backup.minutes),
        type: NotificationType.backup,
        title: 'Hisaab',
        body: 'No backup for $every days. Back up your data now?',
        payload: 'backup',
      ),
    );
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
}
