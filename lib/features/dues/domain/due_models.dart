import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';

enum DueStatus { pending, partial, overdue, settled, cancelled }

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Status is always computed, never stored. It uses the CURRENT due date, so
/// extending the date moves an overdue due back to pending / partial.
DueStatus computeDueStatus({
  required bool cancelled,
  required int remaining,
  required int paid,
  required DateTime currentDueDate,
  required DateTime now,
}) {
  if (cancelled) return DueStatus.cancelled;
  if (remaining <= 0) return DueStatus.settled;
  if (dateOnly(now).isAfter(dateOnly(currentDueDate))) {
    return DueStatus.overdue;
  }
  return paid > 0 ? DueStatus.partial : DueStatus.pending;
}

/// Days late, counted from the ORIGINAL due date (never the extended one).
/// Settled dues use the date of the last payment; open dues use today.
int computeLateDays({
  required DateTime originalDueDate,
  required DateTime now,
  DateTime? settledAt,
}) {
  final reference = settledAt ?? now;
  final days = dateOnly(reference).difference(dateOnly(originalDueDate)).inDays;
  return days > 0 ? days : 0;
}

/// A due plus everything computed from its payments and history.
class DueView {
  const DueView({
    required this.due,
    required this.paid,
    required this.status,
    required this.extensionCount,
    required this.lateDays,
    this.lastPaymentAt,
  });

  final Due due;

  /// Total received (expected income / lent) or paid (borrowed).
  final int paid;
  final DueStatus status;
  final int extensionCount;
  final int lateDays;
  final DateTime? lastPaymentAt;

  int get total => due.totalAmount - due.writtenOffAmount;
  int get remaining {
    final r = total - paid;
    return r < 0 ? 0 : r;
  }

  /// True for dues where money comes to you (expected income, lent).
  bool get isReceivable => due.kind != DueKind.borrowed;
  bool get isOpen =>
      status == DueStatus.pending ||
      status == DueStatus.partial ||
      status == DueStatus.overdue;

  static DueView build({
    required Due due,
    required int paid,
    required int extensionCount,
    required DateTime now,
    DateTime? lastPaymentAt,
  }) {
    final cancelled = due.cancelledAt != null;
    final remaining = due.totalAmount - due.writtenOffAmount - paid;
    final status = computeDueStatus(
      cancelled: cancelled,
      remaining: remaining,
      paid: paid,
      currentDueDate: due.currentDueDate,
      now: now,
    );
    return DueView(
      due: due,
      paid: paid,
      status: status,
      extensionCount: extensionCount,
      lastPaymentAt: lastPaymentAt,
      lateDays: cancelled
          ? 0
          : computeLateDays(
              originalDueDate: due.originalDueDate,
              now: now,
              settledAt: status == DueStatus.settled ? lastPaymentAt : null,
            ),
    );
  }
}

/// On time vs late record for a person or a source (settled dues only).
class TrackRecord {
  const TrackRecord({
    required this.onTime,
    required this.late,
    required this.averageDaysLate,
  });

  final int onTime;
  final int late;

  /// Average of the late dues only; 0 when none were late.
  final double averageDaysLate;

  int get total => onTime + late;
  static const empty = TrackRecord(onTime: 0, late: 0, averageDaysLate: 0);
}

TrackRecord trackRecordFor(Iterable<DueView> views) {
  var onTime = 0;
  var late = 0;
  var lateSum = 0;
  for (final v in views) {
    if (v.status != DueStatus.settled) continue;
    if (v.lateDays > 0) {
      late++;
      lateSum += v.lateDays;
    } else {
      onTime++;
    }
  }
  return TrackRecord(
    onTime: onTime,
    late: late,
    averageDaysLate: late == 0 ? 0 : lateSum / late,
  );
}

/// Net balance with a person: positive means they owe you.
int personNet(Iterable<DueView> views, String personId) {
  var net = 0;
  for (final v in views) {
    if (v.due.personId != personId || !v.isOpen) continue;
    net += v.isReceivable ? v.remaining : -v.remaining;
  }
  return net;
}

/// The next payday on or after [from] for a pay schedule.
/// A payday on the 31st in a shorter month falls on the month's last day.
DateTime? nextPayday({
  required PayScheduleType? type,
  int? payDay,
  int? intervalDays,
  DateTime? anchor,
  required DateTime from,
}) {
  final start = dateOnly(from);
  switch (type) {
    case null:
    case PayScheduleType.irregular:
      return null;
    case PayScheduleType.monthly:
      final day = (payDay ?? 1).clamp(1, 31);
      DateTime inMonth(int year, int month) {
        final last = DateTime(year, month + 1, 0).day;
        return DateTime(year, month, day > last ? last : day);
      }

      var candidate = inMonth(start.year, start.month);
      if (candidate.isBefore(start)) {
        candidate = inMonth(start.year, start.month + 1);
      }
      return candidate;
    case PayScheduleType.weekly:
      final weekday = (payDay ?? 1).clamp(1, 7);
      final diff = (weekday - start.weekday) % 7;
      return start.add(Duration(days: diff));
    case PayScheduleType.everyNDays:
      final n = intervalDays ?? 0;
      if (n <= 0 || anchor == null) return null;
      final a = dateOnly(anchor);
      if (!a.isBefore(start)) return a;
      final elapsed = start.difference(a).inDays;
      final steps = (elapsed + n - 1) ~/ n;
      return DateTime(a.year, a.month, a.day + steps * n);
  }
}
