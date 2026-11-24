import '../../features/ledger/data/ledger_service.dart';

enum PeriodKind { thisMonth, lastMonth, thisYear, allTime }

const periodLabels = {
  PeriodKind.thisMonth: 'This month',
  PeriodKind.lastMonth: 'Last month',
  PeriodKind.thisYear: 'This year',
  PeriodKind.allTime: 'All time',
};

/// Turns a period choice into a date range (end exclusive).
/// [monthStartDay] (1-28) lets a "month" run payday to payday.
DateRange rangeFor(
  PeriodKind kind, {
  int monthStartDay = 1,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startDay = monthStartDay.clamp(1, 28);
  // Start of the month-period that contains [today].
  final thisStart = today.day >= startDay
      ? DateTime(today.year, today.month, startDay)
      : DateTime(today.year, today.month - 1, startDay);
  switch (kind) {
    case PeriodKind.thisMonth:
      return DateRange(
        start: thisStart,
        end: DateTime(thisStart.year, thisStart.month + 1, startDay),
      );
    case PeriodKind.lastMonth:
      return DateRange(
        start: DateTime(thisStart.year, thisStart.month - 1, startDay),
        end: thisStart,
      );
    case PeriodKind.thisYear:
      return DateRange(
        start: DateTime(today.year, 1, 1),
        end: DateTime(today.year + 1, 1, 1),
      );
    case PeriodKind.allTime:
      return DateRange.all;
  }
}
