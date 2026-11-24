import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/utils/period.dart';

void main() {
  test('calendar month', () {
    final r = rangeFor(PeriodKind.thisMonth, now: DateTime(2026, 11, 24));
    expect(r.start, DateTime(2026, 11, 1));
    expect(r.end, DateTime(2026, 12, 1));
  });

  test('last month wraps the year', () {
    final r = rangeFor(PeriodKind.lastMonth, now: DateTime(2027, 1, 10));
    expect(r.start, DateTime(2026, 12, 1));
    expect(r.end, DateTime(2027, 1, 1));
  });

  test('payday-to-payday month starting on the 25th', () {
    final before = rangeFor(
      PeriodKind.thisMonth,
      monthStartDay: 25,
      now: DateTime(2026, 11, 24),
    );
    expect(before.start, DateTime(2026, 10, 25));
    expect(before.end, DateTime(2026, 11, 25));
    final after = rangeFor(
      PeriodKind.thisMonth,
      monthStartDay: 25,
      now: DateTime(2026, 11, 25),
    );
    expect(after.start, DateTime(2026, 11, 25));
    expect(after.end, DateTime(2026, 12, 25));
  });

  test('year and all time', () {
    final y = rangeFor(PeriodKind.thisYear, now: DateTime(2026, 6, 1));
    expect(y.start, DateTime(2026, 1, 1));
    expect(y.end, DateTime(2027, 1, 1));
    expect(rangeFor(PeriodKind.allTime).start, isNull);
  });
}
