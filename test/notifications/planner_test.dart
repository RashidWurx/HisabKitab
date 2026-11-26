import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/dues/domain/due_models.dart';
import 'package:hisaab/features/notifications/domain/notification_models.dart';

const rs = 100;

Due due({
  String id = 'd1',
  DueKind kind = DueKind.lent,
  String? personId = 'ali',
  String? sourceId,
  int total = 5000,
  DateTime? current,
  DateTime? original,
  DateTime? reminderAt,
  int? repeatDays,
  String? periodKey,
  String title = 'Lent to Ali',
}) => Due(
  id: id,
  title: title,
  kind: kind,
  personId: personId,
  sourceId: sourceId,
  totalAmount: total * rs,
  accountId: 'meezan',
  originalDueDate: original ?? current ?? DateTime(2026, 12, 1),
  currentDueDate: current ?? DateTime(2026, 12, 1),
  reminderAt: reminderAt,
  reminderRepeatDays: repeatDays,
  writtenOffAmount: 0,
  periodKey: periodKey,
  createdAt: DateTime(2026, 11, 1),
);

DueView view(Due d, {int paid = 0, DateTime? now}) => DueView.build(
  due: d,
  paid: paid,
  extensionCount: 0,
  now: now ?? DateTime(2026, 11, 25, 12),
);

final people = {
  'ali': PeopleData(
    id: 'ali',
    name: 'Ali',
    isArchived: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  ),
};
final accounts = {
  'meezan': Account(
    id: 'meezan',
    name: 'Meezan Bank',
    type: AccountType.bank,
    openingBalance: 0,
    status: ActiveStatus.active,
    includeInTotal: true,
    colorValue: 1,
    iconKey: 'bank',
    isArchived: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  ),
};

IncomeSource source({ActiveStatus status = ActiveStatus.active}) => IncomeSource(
  id: 'job1',
  name: 'Job 1',
  type: SourceType.job,
  status: status,
  colorValue: 1,
  iconKey: 'work',
  isBuiltIn: false,
  isArchived: false,
  sortOrder: 1,
  createdAt: DateTime(2026, 1, 1),
);

PlanInput input(
  List<DueView> dues, {
  DateTime? now,
  NotificationPrefs prefs = NotificationPrefs.defaults,
  Map<String, IncomeSource> sources = const {},
  List<Subscription> subscriptions = const [],
  List<CustomReminder> reminders = const [],
  DateTime? backupAnchor,
}) => PlanInput(
  now: now ?? DateTime(2026, 11, 25, 12),
  prefs: prefs,
  dues: dues,
  people: people,
  sources: sources,
  accounts: accounts,
  subscriptions: subscriptions,
  reminders: reminders,
  backupAnchor: backupAnchor,
);

NotificationPrefs prefsWith(
  Map<NotificationType, TypePrefs> overrides,
) => NotificationPrefs.fromRaw((key) {
  for (final e in overrides.entries) {
    final t = e.key;
    final p = e.value;
    if (key == NotificationPrefs.keyOf(t, 'enabled')) return p.enabled ? '1' : '0';
    if (key == NotificationPrefs.keyOf(t, 'minutes')) return '${p.minutes}';
    if (key == NotificationPrefs.keyOf(t, 'days')) return '${p.days}';
  }
  return null;
});

void main() {
  group('dues', () {
    test('default: 1 day before and on the due date, at 9:00', () {
      final plan = planReminders(input([view(due())]));
      final times = plan
          .where((r) => r.type == NotificationType.owed)
          .map((r) => r.at)
          .toList();
      expect(times, [DateTime(2026, 11, 30, 9), DateTime(2026, 12, 1, 9)]);
    });

    test('text is short and clear', () {
      final plan = planReminders(input([view(due())]));
      final owed = plan.where((r) => r.type == NotificationType.owed).toList();
      expect(owed.first.body, 'Ali owes you Rs 5,000. Due tomorrow.');
      expect(owed.last.body, 'Ali owes you Rs 5,000. Due today.');
      expect(owed.every((r) => r.payload == 'due:d1' && r.dueActions), isTrue);
    });

    test('you owe someone', () {
      final d = due(kind: DueKind.borrowed, total: 3000);
      final plan = planReminders(input([view(d)]));
      final owe = plan.firstWhere((r) => r.type == NotificationType.owe);
      expect(owe.body, 'You owe Ali Rs 3,000. Due tomorrow.');
    });

    test('payday text names the source and account', () {
      final d = due(
        kind: DueKind.expectedIncome,
        personId: null,
        sourceId: 'job1',
        periodKey: 'job1:2026-12-01',
        title: 'Job 1 salary, Dec 2026',
      );
      final plan = planReminders(input([view(d)], sources: {'job1': source()}));
      final onDay = plan.lastWhere((r) => r.type == NotificationType.payday);
      expect(onDay.body, 'Job 1 salary expected today in Meezan Bank. Received?');
    });

    test('inactive source: no payday reminders', () {
      final d = due(
        kind: DueKind.expectedIncome,
        personId: null,
        sourceId: 'job1',
        periodKey: 'job1:2026-12-01',
      );
      final plan = planReminders(
        input([view(d)], sources: {'job1': source(status: ActiveStatus.inactive)}),
      );
      expect(plan, isEmpty);
    });

    test('per-item override replaces the defaults and can repeat', () {
      final d = due(
        reminderAt: DateTime(2026, 11, 28, 18, 30),
        repeatDays: 2,
      );
      final owed = planReminders(
        input([view(d)]),
      ).where((r) => r.type == NotificationType.owed).toList();
      expect(owed.first.at, DateTime(2026, 11, 28, 18, 30));
      expect(owed[1].at, DateTime(2026, 11, 30, 18, 30));
      expect(owed.length, 5);
      expect(owed.any((r) => r.at == DateTime(2026, 12, 1, 9)), isFalse);
    });

    test('settled and cancelled dues are skipped', () {
      final settled = view(due(), paid: 5000 * rs);
      expect(planReminders(input([settled])), isEmpty);
    });

    test('a disabled type makes no reminders', () {
      final prefs = prefsWith({
        NotificationType.owed: const TypePrefs(enabled: false),
        NotificationType.overdue: const TypePrefs(enabled: false),
      });
      expect(planReminders(input([view(due())], prefs: prefs)), isEmpty);
    });

    test('custom time of day and days before', () {
      final prefs = prefsWith({
        NotificationType.owed: const TypePrefs(minutes: 20 * 60 + 15, days: 3),
      });
      final times = planReminders(input([view(due())], prefs: prefs))
          .where((r) => r.type == NotificationType.owed)
          .map((r) => r.at)
          .toList();
      expect(times, [DateTime(2026, 11, 28, 20, 15), DateTime(2026, 12, 1, 20, 15)]);
    });

    test('reminders in the past are dropped', () {
      final plan = planReminders(
        input([view(due())], now: DateTime(2026, 12, 1, 10)),
      );
      expect(
        plan.where((r) => r.type == NotificationType.owed),
        isEmpty,
      );
    });
  });

  group('overdue nudges', () {
    final overdueDue = due(
      current: DateTime(2026, 11, 20),
      original: DateTime(2026, 11, 15),
    );

    test('start at the next 9:00 and repeat every day by default', () {
      final plan = planReminders(input([view(overdueDue)]));
      final nudges = plan.where((r) => r.type == NotificationType.overdue).toList();
      expect(nudges.map((r) => r.at), [
        DateTime(2026, 11, 26, 9),
        DateTime(2026, 11, 27, 9),
        DateTime(2026, 11, 28, 9),
      ]);
      expect(
        nudges.first.body,
        'Lent to Ali is overdue (late by 11 days). Rs 5,000 remaining.',
      );
    });

    test('every N days', () {
      final prefs = prefsWith({NotificationType.overdue: const TypePrefs(days: 3)});
      final nudges = planReminders(input([view(overdueDue)], prefs: prefs))
          .where((r) => r.type == NotificationType.overdue)
          .map((r) => r.at)
          .toList();
      // Nudges run 21, 24, 27 Nov... (every 3 days from the day after the due date).
      expect(nudges.first, DateTime(2026, 11, 27, 9));
      expect(nudges[1], DateTime(2026, 11, 30, 9));
    });
  });

  group('subscriptions, custom reminders, backup', () {
    Subscription sub({int? daysBefore, SubscriptionStatus status = SubscriptionStatus.active}) =>
        Subscription(
          id: 's1',
          name: 'Spotify',
          amount: 1100 * rs,
          billingUnit: BillingUnit.month,
          billingEvery: 1,
          nextDueDate: DateTime(2026, 11, 26),
          accountId: 'meezan',
          reminderDaysBefore: daysBefore,
          status: status,
          createdAt: DateTime(2026, 1, 1),
        );

    test('renewal text', () {
      final plan = planReminders(input(const [], subscriptions: [sub()]));
      expect(plan.length, 1); // the day-before time is already past
      expect(plan.single.body, 'Spotify renews today: Rs 1,100 from Meezan Bank.');
      expect(plan.single.payload, 'sub:s1');
    });

    test('own days-before overrides the default', () {
      final plan = planReminders(input(const [], subscriptions: [sub(daysBefore: 2)]));
      expect(plan.map((r) => r.at), contains(DateTime(2026, 11, 26, 9)));
      expect(plan.first.body, contains('renews'));
    });

    test('paused subscriptions are silent', () {
      expect(
        planReminders(
          input(const [], subscriptions: [sub(status: SubscriptionStatus.paused)]),
        ),
        isEmpty,
      );
    });

    test('custom reminders: one-off and repeating', () {
      final once = CustomReminder(
        id: 'r1',
        title: 'Pay rent',
        amount: 20000 * rs,
        remindAt: DateTime(2026, 11, 27, 8),
        repeat: ReminderRepeat.none,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final weekly = CustomReminder(
        id: 'r2',
        title: 'Send money home',
        remindAt: DateTime(2026, 11, 26, 10),
        repeat: ReminderRepeat.weekly,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final plan = planReminders(input(const [], reminders: [once, weekly]));
      // With an amount it is a planned payment: asked on the date, then
      // nudged while unpaid.
      final payment = plan.where((r) => r.payload == 'pay:r1').toList();
      expect(payment.where((r) => r.type == NotificationType.custom).length, 1);
      expect(payment.where((r) => r.type == NotificationType.overdue).length, 3);
      expect(plan.where((r) => r.payload == 'reminder:r2').length, 3);
      expect(plan.first.title, 'Send money home');
    });

    test('backup reminder after N days without a backup', () {
      final plan = planReminders(
        input(const [], backupAnchor: DateTime(2026, 11, 20, 15)),
      );
      expect(plan.single.type, NotificationType.backup);
      expect(plan.single.at, DateTime(2026, 11, 27, 9));
    });
  });

  test('only the nearest 60 are kept, soonest first', () {
    final many = [
      for (var i = 0; i < 40; i++)
        view(due(id: 'd$i', current: DateTime(2026, 12, 1).add(Duration(days: i)))),
    ];
    final plan = planReminders(input(many));
    expect(plan.length, maxScheduled);
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
    }
    expect(plan.first.at, DateTime(2026, 11, 30, 9));
  });

  test('prefs default and parse', () {
    expect(NotificationPrefs.defaults.of(NotificationType.backup).days, 7);
    final p = prefsWith({NotificationType.payday: const TypePrefs(enabled: false, minutes: 600, days: 2)});
    expect(p.of(NotificationType.payday).enabled, isFalse);
    expect(p.of(NotificationType.payday).minutes, 600);
    expect(p.of(NotificationType.payday).days, 2);
    expect(p.of(NotificationType.owe).enabled, isTrue);
  });
}
