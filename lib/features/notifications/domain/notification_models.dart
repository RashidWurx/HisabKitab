import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/utils/money.dart';
import '../../dues/domain/due_models.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../thirdparty/domain/pass_models.dart';

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

/// How reminders sound (Android). Settings keys: `notif.sound_uri`,
/// `notif.sound_title`, `notif.alarm_stream`, `notif.keep_ringing`.
class SoundPrefs {
  const SoundPrefs({
    this.uri,
    this.title,
    this.alarmStream = true,
    this.keepRinging = true,
  });

  /// `content://` ringtone chosen with the system picker; null = default.
  final String? uri;
  final String? title;

  /// Play on the alarm volume (louder, ignores silent mode) instead of the
  /// notification volume.
  final bool alarmStream;

  /// Repeat the sound until the user opens or dismisses the notification.
  final bool keepRinging;

  static const defaults = SoundPrefs();

  static const uriKey = 'notif.sound_uri';
  static const titleKey = 'notif.sound_title';
  static const alarmKey = 'notif.alarm_stream';
  static const ringingKey = 'notif.keep_ringing';

  factory SoundPrefs.fromRaw(String? Function(String key) get) {
    final uri = get(uriKey);
    return SoundPrefs(
      uri: (uri == null || uri.isEmpty) ? null : uri,
      title: get(titleKey),
      alarmStream: (get(alarmKey) ?? '1') == '1',
      keepRinging: (get(ringingKey) ?? '1') == '1',
    );
  }

  /// Android fixes a channel's sound when it is created, so the channel id
  /// encodes the sound and volume choice. A new choice means a new channel.
  String get channelId {
    var h = 0;
    for (final c in (uri ?? 'default').codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 'hisaab_r_${alarmStream ? 'a' : 'n'}_${h.toRadixString(36)}';
  }
}

/// Stable 31-bit id for a scheduled notification, so a new alarm never
/// overwrites a different notification that is still in the shade.
int notificationIdFor(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
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
    this.keyOverride,
  });

  /// Used by snoozed copies, which keep the key of their log row.
  final String? keyOverride;

  final DateTime at;
  final NotificationType type;
  final String title;
  final String body;

  /// Where tapping goes: `due:<id>`, `sub:<id>`, `reminder:<id>`, `backup`.
  final String payload;

  /// Due and payday notifications get "Received" / "Extend" buttons.
  final bool dueActions;

  /// Identity of this notification: what it is about and when it fires.
  /// Stable across re-plans, so ids and the inbox rows stay the same.
  String get key =>
      keyOverride ?? '${type.name}|$payload@${at.millisecondsSinceEpoch}';
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
    this.passes = const [],
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
  final List<PassView> passes;

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
      final payload = r.isPayment ? 'pay:${r.id}' : 'reminder:${r.id}';
      var at = r.remindAt;
      for (var i = 0; i < 3; i++) {
        add(
          PlannedReminder(
            at: at,
            type: NotificationType.custom,
            title: r.title,
            body: r.isPayment
                ? 'You had to pay ${Money.format(r.amount!)} today. Have you paid?'
                : 'Reminder',
            payload: payload,
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

      // An unpaid planned payment keeps asking, from the day after its date.
      final nudge = input.prefs.of(NotificationType.overdue);
      if (!r.isPayment || !nudge.enabled) continue;
      final every = nudge.days < 1 ? 1 : nudge.days;
      final due = _day(r.remindAt);
      final following = nextReminderTime(
        at: r.remindAt,
        repeat: r.repeat,
        everyDays: r.repeatEveryDays,
      );
      var day = DateTime(due.year, due.month, due.day + 1);
      var guard = 0;
      while (!_atMinutes(day, nudge.minutes).isAfter(now) && guard++ < 4000) {
        day = DateTime(day.year, day.month, day.day + every);
      }
      for (var i = 0; i < 3; i++) {
        final nudgeAt = _atMinutes(
          DateTime(day.year, day.month, day.day + i * every),
          nudge.minutes,
        );
        // A next occurrence still ahead asks for itself. Once that has passed
        // too, the payment is still unpaid and the nudges carry on.
        if (following != null &&
            following.isAfter(now) &&
            !nudgeAt.isBefore(following)) {
          break;
        }
        add(
          PlannedReminder(
            at: nudgeAt,
            type: NotificationType.overdue,
            title: r.title,
            body:
                '${Money.format(r.amount!)} was due on ${_shortDate(due)}. Have you paid?',
            payload: payload,
          ),
        );
      }
    }
  }

  // ---- 3rd party money ------------------------------------------------------
  for (final v in input.passes) {
    final payload = 'pass:${v.pass.id}';
    final lender = input.people[v.pass.fromPersonId]?.name ?? 'the lender';
    final receiver = input.people[v.pass.forPersonId]?.name ?? 'Someone';

    void side(NotificationType type, DateTime? date, int amount, String text) {
      if (date == null || amount <= 0) return;
      final prefs = input.prefs.of(type);
      final dueDay = _day(date);
      if (prefs.enabled) {
        for (final before in {0, prefs.days}) {
          final at = _atMinutes(
            DateTime(dueDay.year, dueDay.month, dueDay.day - before),
            prefs.minutes,
          );
          add(
            PlannedReminder(
              at: at,
              type: type,
              title: '3rd party money',
              body: '$text Due ${_when(dueDay, at)}.',
              payload: payload,
            ),
          );
        }
      }
      final nudge = input.prefs.of(NotificationType.overdue);
      if (!prefs.enabled || !nudge.enabled) return;
      final every = nudge.days < 1 ? 1 : nudge.days;
      var day = DateTime(dueDay.year, dueDay.month, dueDay.day + 1);
      var guard = 0;
      while (!_atMinutes(day, nudge.minutes).isAfter(now) && guard++ < 4000) {
        day = DateTime(day.year, day.month, day.day + every);
      }
      for (var i = 0; i < 3; i++) {
        add(
          PlannedReminder(
            at: _atMinutes(
              DateTime(day.year, day.month, day.day + i * every),
              nudge.minutes,
            ),
            type: NotificationType.overdue,
            title: '3rd party money',
            body: '$text It was due on ${_shortDate(dueDay)}.',
            payload: payload,
          ),
        );
      }
    }

    side(
      NotificationType.owed,
      v.pass.collectBy,
      v.toCollect,
      'Collect ${Money.format(v.toCollect)} from $receiver (to return to $lender).',
    );
    side(
      NotificationType.owe,
      v.pass.returnBy,
      v.toPayBack,
      'Return ${Money.format(v.toPayBack)} to $lender (borrowed for $receiver).',
    );
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
