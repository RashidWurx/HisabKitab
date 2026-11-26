import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers.dart';
import '../../../core/utils/period.dart';
import '../../ledger/data/ledger_service.dart';
import '../../settings/data/settings_repository.dart';
import '../data/dashboard_service.dart';

/// What the Home period switcher is set to. [kind] is null for a custom range.
class PeriodSelection {
  const PeriodSelection.preset(PeriodKind this.kind) : custom = null;
  const PeriodSelection.custom(DateRange this.custom) : kind = null;

  final PeriodKind? kind;
  final DateRange? custom;

  static const fallback = PeriodSelection.preset(PeriodKind.thisMonth);

  /// How the choice is stored: a [PeriodKind] name, or
  /// `custom:<start millis>:<end millis>`.
  String encode() => custom == null
      ? kind!.name
      : 'custom:${custom!.start!.millisecondsSinceEpoch}'
            ':${custom!.end!.millisecondsSinceEpoch}';

  /// Anything unknown or damaged reads as "This month".
  static PeriodSelection decode(String? raw) {
    if (raw == null) return fallback;
    final parts = raw.split(':');
    if (parts.length == 3 && parts.first == 'custom') {
      final start = int.tryParse(parts[1]);
      final end = int.tryParse(parts[2]);
      if (start == null || end == null) return fallback;
      return PeriodSelection.custom(
        DateRange(
          start: DateTime.fromMillisecondsSinceEpoch(start),
          end: DateTime.fromMillisecondsSinceEpoch(end),
        ),
      );
    }
    for (final k in PeriodKind.values) {
      if (k.name == raw) return PeriodSelection.preset(k);
    }
    return fallback;
  }
}

class PeriodNotifier extends Notifier<PeriodSelection> {
  /// The choice is saved, so it stays until the user changes it.
  @override
  PeriodSelection build() => PeriodSelection.decode(
    ref.watch(
      settingsProvider.select((s) => s.value?.raw(SettingKeys.homePeriod)),
    ),
  );

  void selectPreset(PeriodKind kind) => _choose(PeriodSelection.preset(kind));

  /// [end] is inclusive here (what the date picker returns).
  void selectCustom(DateTime start, DateTime end) => _choose(
    PeriodSelection.custom(
      DateRange(
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day + 1),
      ),
    ),
  );

  void _choose(PeriodSelection selection) {
    state = selection;
    ref
        .read(settingsRepositoryProvider)
        .set(SettingKeys.homePeriod, selection.encode());
  }
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
