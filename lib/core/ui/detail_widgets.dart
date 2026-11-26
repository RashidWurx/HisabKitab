import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../database/app_database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../utils/period.dart';
import '../../features/ledger/data/ledger_service.dart';

/// "This month ▾" style period dropdown.
class PeriodMenu extends StatelessWidget {
  const PeriodMenu({super.key, required this.value, required this.onChanged});

  final PeriodKind value;
  final ValueChanged<PeriodKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PeriodKind>(
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final p in PeriodKind.values)
          PopupMenuItem(value: p, child: Text(periodLabels[p]!)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              periodLabels[value]!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }
}

/// Segmented percentage bar (navy shades), like "Balance by source".
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.amounts});

  /// Positive amounts only; others are ignored.
  final List<int> amounts;

  @override
  Widget build(BuildContext context) {
    final positive = amounts.where((a) => a > 0).toList();
    final total = positive.fold<int>(0, (s, a) => s + a);
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            for (var i = 0; i < positive.length; i++)
              Expanded(
                flex: positive[i],
                child: Container(
                  color: context.series(i),
                  alignment: Alignment.center,
                  child: Text(
                    '${(positive[i] * 100 / total).round()}%',
                    style: TextStyle(
                      color: context.onSeries(i),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Category spending as labelled progress bars.
class CategoryBars extends StatelessWidget {
  const CategoryBars({
    super.key,
    required this.spend,
    required this.categories,
  });

  final List<CategorySpend> spend;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final total = spend.fold<int>(0, (s, e) => s + e.amount);
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No spending in this period.'),
      );
    }
    return Column(
      children: [
        for (final s in spend)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    categories[s.categoryId]?.name ?? 'Uncategorised',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: s.amount / total,
                      minHeight: 12,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      color: context.isDark ? Colors.white : AppTheme.navyMid,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    Money.format(s.amount),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Reads the month-start-day setting for period maths.
int monthStartDayOf(WidgetRef ref) =>
    ref.watch(settingsProvider).value?.monthStartDay ?? 1;
