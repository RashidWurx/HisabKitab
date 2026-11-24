import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/period.dart';
import '../../ledger/data/ledger_service.dart';
import '../data/dashboard_service.dart';
import 'dashboard_charts.dart';
import 'home_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final cats = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };
    final balances = ref.watch(sourceBalancesProvider).value ?? const {};
    final accountBalances = LedgerService.accountTotals(balances);
    final sourceTotals = LedgerService.sourceTotals(balances);
    final headline = LedgerService.headlineTotals(accounts, accountBalances);
    final range = ref.watch(dashboardRangeProvider);
    final totals = ref.watch(periodTotalsProvider((range, null))).value;
    final dues = ref.watch(dueSummaryProvider).value ?? DueSummary.empty;
    final sourceRows = ref.watch(sourceRowsProvider(range)).value ?? const {};
    final accountRows = ref.watch(accountRowsProvider(range)).value ?? const {};
    final upcoming = ref.watch(upcomingProvider).value ?? const [];
    final spend =
        ref.watch(spendingByCategoryProvider((range, null, null))).value ??
        const [];
    final monthly = ref.watch(monthlyTotalsProvider).value;
    final colors = context.appColors;

    final visibleAccounts = accounts.where((a) => !a.isArchived).toList();
    final accountById = {for (final a in accounts) a.id: a};

    final remaining = (totals?.moneyIn ?? 0) - (totals?.moneyOut ?? 0);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text(
          'Hisaab',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26),
        ),
        actions: [
          const _PeriodSwitcher(),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _rangeLabel(range),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // Total balance
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.navyHero,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total balance',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Money.format(headline.total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Includes ${Money.format(headline.savings)} in savings',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Income / Expense / Remaining
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _stat(
                      context,
                      'Income',
                      MoneyText(totals?.moneyIn ?? 0, style: _statStyle),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _stat(
                      context,
                      'Expense',
                      MoneyText(
                        totals?.moneyOut ?? 0,
                        forceColor: (totals?.moneyOut ?? 0) == 0
                            ? null
                            : colors.negative,
                        style: _statStyle,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _stat(
                      context,
                      'Remaining',
                      MoneyText(remaining, style: _statStyle),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // To receive / To pay
          Row(
            children: [
              Expanded(
                child: _dueTile(
                  context,
                  icon: Icons.arrow_downward,
                  label: 'To receive',
                  amount: dues.toReceive,
                  color: colors.positive,
                  extra: dues.overdueCount > 0
                      ? Text(
                          '${dues.overdueCount} overdue',
                          style: TextStyle(
                            color: colors.negative,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dueTile(
                  context,
                  icon: Icons.arrow_upward,
                  label: 'To pay',
                  amount: dues.toPay,
                  color: colors.negative,
                ),
              ),
            ],
          ),
          // Money by source
          const SectionTitle('Money by source'),
          _moneyBySource(
            context,
            sources: sources,
            rows: sourceRows,
            left: sourceTotals,
            accountById: accountById,
          ),
          // Accounts
          SectionTitle(
            'Accounts',
            trailing: TextButton(
              onPressed: () => context.push('/accounts'),
              child: const Text('Manage'),
            ),
          ),
          if (visibleAccounts.isEmpty)
            SizedBox(
              height: 240,
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message: 'Add an account to start tracking your money.',
                actionLabel: 'Add account',
                onAction: () => context.push('/accounts/new'),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < visibleAccounts.length; i++) ...[
                    if (i > 0) const Divider(),
                    _accountRow(
                      context,
                      visibleAccounts[i],
                      accountBalances[visibleAccounts[i].id] ?? 0,
                      accountRows[visibleAccounts[i].id],
                    ),
                  ],
                ],
              ),
            ),
          // Upcoming
          const SectionTitle('Upcoming (next 7 days)'),
          if (upcoming.isEmpty)
            const AppCard(child: Text('Nothing due in the next 7 days.'))
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < upcoming.length; i++) ...[
                    if (i > 0) const Divider(),
                    _upcomingRow(context, upcoming[i]),
                  ],
                ],
              ),
            ),
          // Charts
          const SectionTitle('Spending by category'),
          AppCard(child: SpendingDonut(spend: spend, categories: cats)),
          const SectionTitle('Income vs expense'),
          AppCard(
            child: monthly == null
                ? const SizedBox(height: 120)
                : IncomeExpenseBars(
                    ranges: monthly.ranges,
                    totals: monthly.totals,
                    incomeColor: colors.positive,
                    expenseColor: colors.negative,
                  ),
          ),
        ],
      ),
    );
  }

  static const _statStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);

  TextStyle _subStyle(BuildContext context) => TextStyle(
    fontSize: 13,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  Widget _stat(BuildContext context, String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: value),
      ],
    ),
  );

  Widget _dueTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int amount,
    required Color color,
    Widget? extra,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.go('/dues'),
      child: Row(
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    Money.format(amount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: amount == 0 ? null : color,
                    ),
                  ),
                ),
                ?extra,
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _moneyBySource(
    BuildContext context, {
    required List<IncomeSource> sources,
    required Map<String, SourceDashRow> rows,
    required Map<String, int> left,
    required Map<String, Account> accountById,
  }) {
    final shown = <IncomeSource>[];
    for (final s in sources) {
      if (s.isArchived) continue;
      final r = rows[s.id];
      final any =
          (r?.received ?? 0) != 0 ||
          (r?.spent ?? 0) != 0 ||
          (r?.expected ?? 0) != 0 ||
          (left[s.id] ?? 0) != 0;
      final alwaysShow = !s.isBuiltIn && s.status == ActiveStatus.active;
      if (any || alwaysShow) shown.add(s);
    }
    if (shown.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Expanded(
              child: Text('Add an income source to see where your money comes from.'),
            ),
            TextButton(
              onPressed: () => context.push('/sources/new'),
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }
    final colors = context.appColors;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(),
            Builder(
              builder: (_) {
                final s = shown[i];
                final r = rows[s.id];
                final leftNow = left[s.id] ?? 0;
                final expected = r?.expected ?? 0;
                final into = accountById[r?.expectedAccountId]?.name;
                return InkWell(
                  onTap: () => context.push('/sources/${s.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        IconBox(
                          iconKey: s.iconKey,
                          color: Color(s.colorValue),
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Received ${Money.format(r?.received ?? 0)}',
                                style: _subStyle(context),
                              ),
                              Text(
                                'Spent ${Money.format(r?.spent ?? 0)}',
                                style: _subStyle(context),
                              ),
                              if (expected > 0)
                                Text(
                                  'Expecting ${Money.format(expected)}${into == null ? '' : ' into $into'}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.pending,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Left', style: TextStyle(fontSize: 12)),
                            MoneyText(
                              leftNow,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountRow(
    BuildContext context,
    Account a,
    int balance,
    AccountDashRow? row,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final expected = row?.expected ?? 0;
    return InkWell(
      onTap: () => context.push('/accounts/${a.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBox(iconKey: a.iconKey, color: Color(a.colorValue), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Wrap(
                    spacing: 14,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(text: 'In '),
                            TextSpan(
                              text: Money.format(row?.moneyIn ?? 0),
                              style: TextStyle(
                                color: (row?.moneyIn ?? 0) == 0
                                    ? null
                                    : colors.positive,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(text: 'Out '),
                            TextSpan(
                              text: Money.format(row?.moneyOut ?? 0),
                              style: TextStyle(
                                color: (row?.moneyOut ?? 0) == 0
                                    ? null
                                    : colors.negative,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (expected > 0)
                    Text(
                      'Expecting ${Money.format(expected)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.pending,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            MoneyText(
              balance,
              neutral: balance >= 0,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcomingRow(BuildContext context, UpcomingItem item) {
    final colors = context.appColors;
    final icon = switch (item.kind) {
      UpcomingKind.due => Icons.event_outlined,
      UpcomingKind.subscription => Icons.autorenew,
      UpcomingKind.reminder => Icons.notifications_none,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(DateFormat('d MMM').format(item.date)),
          ),
          Expanded(
            child: Text(
              item.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (item.amount != null)
            Text(
              Money.format(item.isMoneyIn ? item.amount! : -item.amount!),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: item.isMoneyIn ? colors.positive : colors.negative,
              ),
            ),
        ],
      ),
    );
  }

  String _rangeLabel(DateRange r) {
    if (r.start == null || r.end == null) return 'All time';
    final f = DateFormat('d MMM y');
    final last = r.end!.subtract(const Duration(days: 1));
    return '${f.format(r.start!)} – ${f.format(last)}';
  }
}

/// "This month ▾" menu with presets and a custom range.
class _PeriodSwitcher extends ConsumerWidget {
  const _PeriodSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(periodSelectionProvider);
    final notifier = ref.read(periodSelectionProvider.notifier);
    final label = selection.kind == null
        ? 'Custom range'
        : periodLabels[selection.kind]!;
    return PopupMenuButton<Object>(
      onSelected: (v) async {
        if (v is PeriodKind) {
          notifier.selectPreset(v);
          return;
        }
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) notifier.selectCustom(picked.start, picked.end);
      },
      itemBuilder: (_) => [
        for (final p in PeriodKind.values)
          PopupMenuItem<Object>(value: p, child: Text(periodLabels[p]!)),
        const PopupMenuItem<Object>(value: 'custom', child: Text('Custom range…')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }
}
