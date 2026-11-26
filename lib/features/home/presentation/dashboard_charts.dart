import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../data/dashboard_service.dart';

/// Spending by category as a donut with a legend.
class SpendingDonut extends StatelessWidget {
  const SpendingDonut({
    super.key,
    required this.spend,
    required this.categories,
  });

  final List<CategorySpend> spend;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final slices = DashboardService.topWithOther(spend, 5);
    final total = slices.fold<int>(0, (s, e) => s + e.amount);
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No spending in this period yet.'),
      );
    }
    Color colorOf(CategorySpend s, int i) {
      final c = categories[s.categoryId];
      if (c != null && !context.isDark) return Color(c.colorValue);
      return context.series(i);
    }

    String nameOf(CategorySpend s) {
      if (s.categoryId == DashboardService.otherCategoriesId) {
        return 'Other categories';
      }
      return categories[s.categoryId]?.name ?? 'Uncategorised';
    }

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PieChart(
            duration: Duration.zero,
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 54,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].amount.toDouble(),
                    color: colorOf(slices[i], i),
                    radius: 34,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colorOf(slices[i], i),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(nameOf(slices[i]))),
                Text(
                  '${(slices[i].amount * 100 / total).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 96,
                  child: Text(
                    Money.format(slices[i].amount),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Income vs expense for the last months (grouped bars).
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars({
    super.key,
    required this.ranges,
    required this.totals,
    required this.incomeColor,
    required this.expenseColor,
  });

  final List<DateRange> ranges;
  final List<AccountPeriodStats> totals;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    final any = totals.any((t) => t.moneyIn > 0 || t.moneyOut > 0);
    if (!any) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Add income and expenses to see the last 6 months.'),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            duration: Duration.zero,
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    Money.format((rod.toY * 100).round()),
                    TextStyle(
                      color: rod.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= ranges.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          DateFormat('MMM').format(ranges[i].start!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < totals.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: totals[i].moneyIn / 100,
                        color: incomeColor,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: totals[i].moneyOut / 100,
                        color: expenseColor,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(incomeColor, 'Income'),
            const SizedBox(width: 20),
            _legend(expenseColor, 'Expense'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String text) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(text),
    ],
  );
}
