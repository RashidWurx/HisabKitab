import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds [months] to [from], using [day] as the target day of the month
/// (clamped to the last day of a shorter month). Passing the original
/// billing day keeps a 31st subscription on the 31st after a short month.
DateTime addMonths(DateTime from, int months, {int? day}) {
  final targetDay = day ?? from.day;
  final totalMonths = from.year * 12 + (from.month - 1) + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, targetDay > last ? last : targetDay);
}

/// The billing date after [from] for "every [every] [unit]".
DateTime nextBillingDate({
  required DateTime from,
  required BillingUnit unit,
  required int every,
  int? anchorDay,
}) {
  final n = every < 1 ? 1 : every;
  final start = _dateOnly(from);
  switch (unit) {
    case BillingUnit.day:
      return DateTime(start.year, start.month, start.day + n);
    case BillingUnit.week:
      return DateTime(start.year, start.month, start.day + 7 * n);
    case BillingUnit.month:
      return addMonths(start, n, day: anchorDay);
    case BillingUnit.year:
      return addMonths(start, 12 * n, day: anchorDay);
  }
}

/// What a subscription costs per month, in paisa (yearly / 12, weekly x 52 / 12).
int monthlyCost({
  required int amount,
  required BillingUnit unit,
  required int every,
}) {
  final n = every < 1 ? 1 : every;
  int ratio(int numerator, int denominator) =>
      (amount * numerator + denominator ~/ 2) ~/ denominator;
  switch (unit) {
    case BillingUnit.day:
      return ratio(365, 12 * n);
    case BillingUnit.week:
      return ratio(52, 12 * n);
    case BillingUnit.month:
      return ratio(1, n);
    case BillingUnit.year:
      return ratio(1, 12 * n);
  }
}

/// Monthly cost of all ACTIVE subscriptions.
int totalMonthlyCost(Iterable<Subscription> subscriptions) {
  var total = 0;
  for (final s in subscriptions) {
    if (s.status != SubscriptionStatus.active) continue;
    total += monthlyCost(
      amount: s.amount,
      unit: s.billingUnit,
      every: s.billingEvery,
    );
  }
  return total;
}

String billingLabel(BillingUnit unit, int every) {
  final n = every < 1 ? 1 : every;
  if (n == 1) {
    return switch (unit) {
      BillingUnit.day => 'day',
      BillingUnit.week => 'week',
      BillingUnit.month => 'month',
      BillingUnit.year => 'year',
    };
  }
  return switch (unit) {
    BillingUnit.day => '$n days',
    BillingUnit.week => '$n weeks',
    BillingUnit.month => '$n months',
    BillingUnit.year => '$n years',
  };
}
