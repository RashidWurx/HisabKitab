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
import '../../notifications/presentation/missed_page.dart';
import 'dashboard_charts.dart';
import 'home_providers.dart';

// Light tints that stay readable on the navy hero card.
const _heroGreen = Color(0xFF7DE3A0);
const _heroRed = Color(0xFFFF9A92);

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
        titleSpacing: 20,
        toolbarHeight: 64,
        title: const Text(
          'Hisaab',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 28,
            letterSpacing: -0.6,
          ),
        ),
        actions: const [_PeriodSwitcher(), _MissedBell(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 128),
        children: [
          // ---- Hero ----
          _Hero(
            total: headline.total,
            savings: headline.savings,
            income: totals?.moneyIn ?? 0,
            expense: totals?.moneyOut ?? 0,
            remaining: remaining,
            rangeLabel: _rangeLabel(range),
          ),
          const SizedBox(height: 16),
          // ---- Quick actions ----
          const _QuickActions(),
          const SizedBox(height: 16),
          // ---- Dues ----
          Row(
            children: [
              Expanded(
                child: _DueTile(
                  icon: Icons.south_west_rounded,
                  label: 'To receive',
                  amount: dues.toReceive,
                  color: colors.positive,
                  route: '/dues',
                  badge: dues.overdueCount > 0
                      ? '${dues.overdueCount} overdue'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DueTile(
                  icon: Icons.north_east_rounded,
                  label: 'To pay',
                  amount: dues.toPay,
                  color: colors.negative,
                  route: '/dues?tab=pay',
                ),
              ),
            ],
          ),
          // ---- Accounts ----
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
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: visibleAccounts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = visibleAccounts[i];
                  return _AccountCard(
                    account: a,
                    balance: accountBalances[a.id] ?? 0,
                    row: accountRows[a.id],
                  );
                },
              ),
            ),
          // ---- Money by source ----
          const SectionTitle('Money by source'),
          _moneyBySource(
            context,
            sources: sources,
            rows: sourceRows,
            left: sourceTotals,
            accountById: accountById,
          ),
          // ---- Upcoming ----
          const SectionTitle('Upcoming · next 7 days'),
          if (upcoming.isEmpty)
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.event_available_outlined),
                  SizedBox(width: 12),
                  Expanded(child: Text('Nothing due in the next 7 days.')),
                ],
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < upcoming.length; i++) ...[
                    if (i > 0) const Divider(indent: 76),
                    _UpcomingRow(item: upcoming[i]),
                  ],
                ],
              ),
            ),
          // ---- Charts ----
          const SectionTitle('Spending by category'),
          RepaintBoundary(
            child: AppCard(child: SpendingDonut(spend: spend, categories: cats)),
          ),
          const SectionTitle('Income vs expense'),
          RepaintBoundary(
            child: AppCard(
              child: monthly == null
                  ? const SizedBox(height: 120)
                  : IncomeExpenseBars(
                      ranges: monthly.ranges,
                      totals: monthly.totals,
                      incomeColor: colors.positive,
                      expenseColor: colors.negative,
                    ),
            ),
          ),
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
              child: Text(
                'Add an income source to see where your money comes from.',
              ),
            ),
            TextButton(
              onPressed: () => context.push('/sources/new'),
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SourceCard(
              source: s,
              row: rows[s.id],
              left: left[s.id] ?? 0,
              expectedInto: accountById[rows[s.id]?.expectedAccountId]?.name,
            ),
          ),
      ],
    );
  }

  String _rangeLabel(DateRange r) {
    if (r.start == null || r.end == null) return 'All time';
    final f = DateFormat('d MMM');
    final last = r.end!.subtract(const Duration(days: 1));
    return '${f.format(r.start!)} – ${f.format(last)}';
  }
}

// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.total,
    required this.savings,
    required this.income,
    required this.expense,
    required this.remaining,
    required this.rangeLabel,
  });

  final int total;
  final int savings;
  final int income;
  final int expense;
  final int remaining;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D4068), AppTheme.navy],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33112E4E),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total balance',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    rangeLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.format(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Includes ${Money.format(savings)} in savings',
              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.south_west_rounded,
                    label: 'Income',
                    value: Money.format(income),
                    color: income == 0 ? Colors.white : _heroGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.north_east_rounded,
                    label: 'Expense',
                    value: Money.format(expense),
                    color: expense == 0 ? Colors.white : _heroRed,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.savings_outlined,
                    label: 'Remaining',
                    value: Money.format(remaining),
                    color: remaining == 0
                        ? Colors.white
                        : (remaining > 0 ? _heroGreen : _heroRed),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xB3FFFFFF)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.remove_rounded, 'Expense', '/transaction/new/expense'),
      (Icons.add_rounded, 'Income', '/transaction/new/income'),
      (Icons.swap_horiz_rounded, 'Transfer', '/transaction/new/transfer'),
      (Icons.volunteer_activism_outlined, 'Lend', '/dues/new/lent'),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final it in items)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push(it.$3),
            child: SizedBox(
              width: 76,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(it.$1, color: scheme.primary, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    it.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
    required this.route,
    this.badge,
  });

  final IconData icon;
  final String label;
  final int amount;
  final Color color;
  final String route;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.go(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(amount),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: amount == 0 ? null : color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                badge!,
                style: TextStyle(
                  color: colors.negative,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.balance,
    required this.row,
  });

  final Account account;
  final int balance;
  final AccountDashRow? row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final tint = Color(account.colorValue);
    final dark = scheme.brightness == Brightness.dark;
    return SizedBox(
      width: 232,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: dark ? 0.30 : 0.16),
              scheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/accounts/${account.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBox(
                        iconKey: account.iconKey,
                        color: tint,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          account.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MoneyText(
                      balance,
                      neutral: balance >= 0,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.south_west_rounded, size: 13, color: colors.positive),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          Money.format(row?.moneyIn ?? 0),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.north_east_rounded, size: 13, color: colors.negative),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          Money.format(row?.moneyOut ?? 0),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.row,
    required this.left,
    required this.expectedInto,
  });

  final IncomeSource source;
  final SourceDashRow? row;
  final int left;
  final String? expectedInto;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final received = row?.received ?? 0;
    final spent = row?.spent ?? 0;
    final expected = row?.expected ?? 0;
    final tint = Color(source.colorValue);
    final ratio = received > 0 ? spent / received : (spent > 0 ? 1.0 : 0.0);
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/sources/${source.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBox(iconKey: source.iconKey, color: tint, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Left now',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              MoneyText(
                left,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!source.isBuiltIn) ...[
            SoftProgress(
              value: ratio,
              color: ratio > 1 ? colors.negative : tint,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: 'Received ',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      TextSpan(
                        text: Money.format(received),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: received == 0 ? null : colors.positive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'Spent ',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    TextSpan(
                      text: Money.format(spent),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: spent == 0 ? null : colors.negative,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (expected > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.pending.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 15, color: colors.pending),
                  const SizedBox(width: 6),
                  Text(
                    'Expecting ${Money.format(expected)}${expectedInto == null ? '' : ' into $expectedInto'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.pending,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.item});

  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final label = switch (item.kind) {
      UpcomingKind.due => item.isMoneyIn ? 'Expected' : 'To pay',
      UpcomingKind.subscription => 'Subscription',
      UpcomingKind.reminder => 'Reminder',
    };
    final color = item.isMoneyIn ? colors.positive : colors.negative;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('d').format(item.date),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(item.date).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (item.amount != null)
            Text(
              Money.format(item.isMoneyIn ? item.amount! : -item.amount!),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// Period pill ("This month ▾") with presets and a custom range.
class _PeriodSwitcher extends ConsumerWidget {
  const _PeriodSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(periodSelectionProvider);
    final notifier = ref.read(periodSelectionProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
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
        const PopupMenuItem<Object>(
          value: 'custom',
          child: Text('Custom range…'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Bell with a count of reminders that were missed; opens the inbox.
class _MissedBell extends ConsumerWidget {
  const _MissedBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(missedCountProvider);
    return IconButton(
      tooltip: 'Missed reminders',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: context.appColors.negative,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}
