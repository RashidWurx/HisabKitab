import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers.dart';
import '../../../core/utils/period.dart';
import '../../ledger/data/ledger_service.dart';
import '../data/dashboard_service.dart';

/// What the Home period switcher is set to. [kind] is null for a custom range.
class PeriodSelection {
  const PeriodSelection.preset(PeriodKind this.kind) : custom = null;
  const PeriodSelection.custom(DateRange this.custom) : kind = null;

  final PeriodKind? kind;
  final DateRange? custom;
}

class PeriodNotifier extends Notifier<PeriodSelection> {
  @override
  PeriodSelection build() => const PeriodSelection.preset(PeriodKind.thisMonth);

  void selectPreset(PeriodKind kind) => state = PeriodSelection.preset(kind);

  /// [end] is inclusive here (what the date picker returns).
  void selectCustom(DateTime start, DateTime end) =>
      state = PeriodSelection.custom(
        DateRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day + 1),
        ),
      );
}

final periodSelectionProvider =
    NotifierProvider<PeriodNotifier, PeriodSelection>(PeriodNotifier.new);

/// The date range for the current selection and month start day setting.
final dashboardRangeProvider = Provider<DateRange>((ref) {
  final selection = ref.watch(periodSelectionProvider);
  final startDay = ref.watch(
    settingsProvider.select((s) => s.value?.monthStartDay ?? 1),
  );
  return selection.custom ??
      rangeFor(selection.kind!, monthStartDay: startDay);
});

final dashboardServiceProvider = Provider(
  (ref) => DashboardService(ref.watch(databaseProvider)),
);

final dueSummaryProvider = StreamProvider<DueSummary>(
  (ref) => ref.watch(dashboardServiceProvider).watchDueSummary(),
);

final sourceRowsProvider =
    StreamProvider.family<Map<String, SourceDashRow>, DateRange>(
      (ref, range) =>
          ref.watch(dashboardServiceProvider).watchSourceRows(range),
    );

final accountRowsProvider =
    StreamProvider.family<Map<String, AccountDashRow>, DateRange>(
      (ref, range) =>
          ref.watch(dashboardServiceProvider).watchAccountRows(range),
    );

final upcomingProvider = StreamProvider<List<UpcomingItem>>(
  (ref) => ref.watch(dashboardServiceProvider).watchUpcoming(),
);

/// Income vs expense for the last 6 month-periods (oldest first).
final monthlyTotalsProvider =
    StreamProvider<({List<DateRange> ranges, List<AccountPeriodStats> totals})>((
      ref,
    ) {
      final startDay = ref.watch(
        settingsProvider.select((s) => s.value?.monthStartDay ?? 1),
      );
      final ranges = lastMonthRanges(6, monthStartDay: startDay);
      return ref
          .watch(dashboardServiceProvider)
          .watchTotalsPerRange(ranges)
          .map((totals) => (ranges: ranges, totals: totals));
    });
