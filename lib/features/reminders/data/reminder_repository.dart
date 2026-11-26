import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../subscriptions/domain/subscription_logic.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_models.dart';

class ReminderDraft {
  const ReminderDraft({
    this.id,
    required this.title,
    this.amount,
    this.categoryId,
    this.accountId,
    required this.remindAt,
    this.repeat = ReminderRepeat.none,
    this.repeatEveryDays,
    this.isActive = true,
  });

  final String? id;
  final String title;
  final int? amount;
  final String? categoryId;
  final String? accountId;
  final DateTime remindAt;
  final ReminderRepeat repeat;
  final int? repeatEveryDays;
  final bool isActive;
}

/// The next time a repeating reminder fires after [at]. Null if it does not
/// repeat. Monthly reminders keep their day of month (31st -> last day).
DateTime? nextReminderTime({
  required DateTime at,
  required ReminderRepeat repeat,
  int? everyDays,
  int? anchorDay,
}) {
  switch (repeat) {
    case ReminderRepeat.none:
      return null;
    case ReminderRepeat.daily:
      return DateTime(at.year, at.month, at.day + 1, at.hour, at.minute);
    case ReminderRepeat.weekly:
      return DateTime(at.year, at.month, at.day + 7, at.hour, at.minute);
    case ReminderRepeat.everyNDays:
      final n = (everyDays ?? 0) < 1 ? 1 : everyDays!;
      return DateTime(at.year, at.month, at.day + n, at.hour, at.minute);
    case ReminderRepeat.monthly:
      final d = addMonths(at, 1, day: anchorDay ?? at.day);
      return DateTime(d.year, d.month, d.day, at.hour, at.minute);
  }
}

/// A reminder with an amount is a planned payment: nothing leaves an account
/// until the user says it was paid. It stays on its date until then.
extension PlannedPayment on CustomReminder {
  bool get isPayment => amount != null;

  /// Its time has come and the user has not recorded it yet.
  bool isUnpaid(DateTime now) =>
      isPayment && isActive && !remindAt.isAfter(now);
}

/// "Add expense" pre-filled from a reminder. For a planned payment, saving
/// that expense also marks this occurrence as paid.
String expenseRouteFor(CustomReminder r) {
  final q = <String, String>{
    if (r.amount != null) 'amount': '${r.amount}',
    if (r.categoryId != null) 'category': r.categoryId!,
    if (r.accountId != null) 'account': r.accountId!,
    if (r.isPayment) ...{
      'reminder': r.id,
      'occurrence': '${r.remindAt.millisecondsSinceEpoch}',
      'note': r.title,
    },
  };
  return Uri(
    path: '/transaction/new/expense',
    queryParameters: q.isEmpty ? null : q,
  ).toString();
}

class ReminderRepository {
  ReminderRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<CustomReminder>> watchAll() => (_db.select(
    _db.customReminders,
  )..orderBy([(r) => OrderingTerm.asc(r.remindAt)])).watch();

  Future<CustomReminder?> get(String id) => (_db.select(
    _db.customReminders,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<String> save(ReminderDraft d) async {
    if (d.title.trim().isEmpty) throw LedgerException('Enter a title.');
    if (d.amount != null && d.amount! <= 0) {
      throw LedgerException('Amount must be above 0.');
    }
    if (d.repeat == ReminderRepeat.everyNDays &&
        (d.repeatEveryDays == null || d.repeatEveryDays! < 1)) {
      throw LedgerException('Enter every how many days.');
    }
    final id = d.id ?? _uuid.v4();
    final existing = await get(id);
    await _db
        .into(_db.customReminders)
        .insertOnConflictUpdate(
          CustomRemindersCompanion(
            id: Value(id),
            title: Value(d.title.trim()),
            amount: Value(d.amount),
            categoryId: Value(d.categoryId),
            accountId: Value(d.accountId),
            remindAt: Value(d.remindAt),
            repeat: Value(d.repeat),
            repeatEveryDays: Value(
              d.repeat == ReminderRepeat.everyNDays ? d.repeatEveryDays : null,
            ),
            isActive: Value(d.isActive),
            createdAt: Value(existing?.createdAt ?? DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> setActive(String id, bool active) =>
      (_db.update(_db.customReminders)..where((r) => r.id.equals(id))).write(
        CustomRemindersCompanion(isActive: Value(active)),
      );

  Future<void> delete(String id) =>
      (_db.delete(_db.customReminders)..where((r) => r.id.equals(id))).go();

  /// Saves the expense for a planned payment and closes that occurrence, in
  /// one database transaction: a one-off payment is switched off, a repeating
  /// one moves to its next date. [occurrence] is the date the user was paying,
  /// so the same payment cannot be recorded twice.
  Future<String> recordPaid(
    String id, {
    required DateTime occurrence,
    required TransactionInput expense,
    DateTime? now,
  }) => _db.transaction(() async {
    final r = await get(id);
    if (r == null) throw LedgerException('This planned payment was deleted.');
    if (!r.isActive ||
        r.remindAt.millisecondsSinceEpoch !=
            occurrence.millisecondsSinceEpoch) {
      throw LedgerException('This payment is already recorded.');
    }
    final txId = await TransactionRepository(_db).save(expense);
    final next = nextReminderTime(
      at: r.remindAt,
      repeat: r.repeat,
      everyDays: r.repeatEveryDays,
    );
    await (_db.update(_db.customReminders)..where((x) => x.id.equals(id)))
        .write(
          next == null
              ? const CustomRemindersCompanion(isActive: Value(false))
              : CustomRemindersCompanion(remindAt: Value(next)),
        );
    // Close its missed reminders and drop any "remind me later" copy.
    final current = now ?? DateTime.now();
    final payload = 'pay:$id';
    await (_db.delete(_db.notificationLog)..where(
          (l) =>
              l.payload.equals(payload) &
              l.isSnooze.equals(true) &
              l.fireAt.isBiggerThanValue(current),
        ))
        .go();
    await (_db.update(_db.notificationLog)..where(
          (l) =>
              l.payload.equals(payload) &
              l.handledAt.isNull() &
              l.fireAt.isSmallerOrEqualValue(current),
        ))
        .write(NotificationLogCompanion(handledAt: Value(current)));
    return txId;
  });

  /// Repeating reminders whose time has passed move to their next time.
  /// One-off reminders stay as they are (they show as "done" once past).
  /// Planned payments never move by themselves, only when paid.
  Future<int> rollForward({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final past =
        await (_db.select(_db.customReminders)..where(
              (r) =>
                  r.isActive.equals(true) &
                  r.amount.isNull() &
                  r.repeat.equals(ReminderRepeat.none.name).not() &
                  r.remindAt.isSmallerThanValue(current),
            ))
            .get();
    var moved = 0;
    for (final r in past) {
      var next = r.remindAt;
      final anchor = r.remindAt.day;
      var guard = 0;
      while (next.isBefore(current) && guard++ < 5000) {
        next =
            nextReminderTime(
              at: next,
              repeat: r.repeat,
              everyDays: r.repeatEveryDays,
              anchorDay: anchor,
            ) ??
            next;
        if (r.repeat == ReminderRepeat.none) break;
      }
      await (_db.update(_db.customReminders)..where((x) => x.id.equals(r.id)))
          .write(CustomRemindersCompanion(remindAt: Value(next)));
      moved++;
    }
    return moved;
  }
}
