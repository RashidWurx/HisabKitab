import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../home/presentation/home_providers.dart';
import '../../../core/ui/detail_widgets.dart';
import '../../../core/ui/icon_registry.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/period.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/presentation/open_transaction.dart';
import '../../transactions/presentation/transaction_tile.dart';
import 'accounts_page.dart';

class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  PeriodKind _period = PeriodKind.thisMonth;

  @override
  Widget build(BuildContext context) {
    final id = widget.accountId;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    Account? account;
    for (final a in accounts) {
      if (a.id == id) account = a;
    }
    if (account == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final cats = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };
    final balances = ref.watch(sourceBalancesProvider).value ?? const {};
    final inAccount = LedgerService.sourcesInAccount(balances, id);
    final total = LedgerService.accountTotals(balances)[id] ?? 0;
    final range = rangeFor(_period, monthStartDay: monthStartDayOf(ref));
    final stats = ref.watch(periodTotalsProvider((range, id))).value;
    final spend =
        ref.watch(spendingByCategoryProvider((range, id, null))).value ??
        const [];
    final recent =
        ref.watch(transactionsProvider(TransactionFilter(accountId: id))).value ??
        const [];
    final expectedIn =
        ref.watch(accountRowsProvider(range)).value?[id]?.expected ?? 0;
    final linked = sources.where((s) => s.linkedAccountId == id).toList();
    final srcById = {for (final s in sources) s.id: s};
    final acctMap = {for (final a in accounts) a.id: a};

    final sourceRows = inAccount.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(accountRepositoryProvider);
              if (v == 'edit') {
                context.push('/accounts/$id/edit');
              } else if (v == 'archive') {
                await repo.setArchived(id, !account!.isArchived);
              } else if (v == 'delete') {
                await deleteAccountFlow(context, ref, id);
                if (!context.mounted) return;
                if (await repo.get(id) == null && context.mounted) {
                  context.pop();
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'archive',
                child: Text(account!.isArchived ? 'Unarchive' : 'Archive'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Row(
            children: [
              IconBox(
                iconKey: account.iconKey,
                color: Color(account.colorValue),
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  account.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Account', style: TextStyle(fontSize: 15)),
          MoneyText(
            total,
            neutral: total >= 0,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
          ),
          const SectionTitle('Balance by source'),
          ShareBar(amounts: [for (final e in sourceRows) e.value]),
          const SizedBox(height: 8),
          if (sourceRows.isEmpty)
            const InlineEmpty(Icons.account_balance_wallet_outlined, 'No money in this account yet.')
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < sourceRows.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      leading: IconBox(
                        iconKey: srcById[sourceRows[i].key]?.iconKey ?? 'wallet',
                        color: srcById[sourceRows[i].key] == null
                            ? null
                            : Color(srcById[sourceRows[i].key]!.colorValue),
                        size: 36,
                      ),
                      title: Text(
                        srcById[sourceRows[i].key]?.name ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            sourceRows[i].value,
                            neutral: sourceRows[i].value >= 0,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => context.push('/sources/${sourceRows[i].key}'),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Money in and out',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              PeriodMenu(
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: [
                InfoRow(
                  'Money in',
                  null,
                  valueWidget: MoneyText(
                    stats?.moneyIn ?? 0,
                    neutral: (stats?.moneyIn ?? 0) == 0,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                InfoRow(
                  'Money out',
                  null,
                  valueWidget: MoneyText(
                    -(stats?.moneyOut ?? 0),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                InfoRow(
                  'Net',
                  null,
                  valueWidget: MoneyText(
                    stats?.net ?? 0,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                InfoRow('Expected to arrive', Money.format(expectedIn)),
                InfoRow(
                  'Margin',
                  stats?.marginPercent == null
                      ? '—'
                      : '${stats!.marginPercent!.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
          if (linked.isNotEmpty) ...[
            const SectionTitle('Linked sources'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in linked)
                  ActionChip(
                    avatar: Icon(iconFor(s.iconKey)),
                    label: Text(s.name),
                    onPressed: () => context.push('/sources/${s.id}'),
                  ),
              ],
            ),
          ],
          const SectionTitle('Spending by category'),
          CategoryBars(spend: spend, categories: cats),
          SectionTitle(
            'Transactions',
            trailing: TextButton(
              onPressed: () => context.push('/activity?account=$id'),
              child: const Text('See all'),
            ),
          ),
          if (recent.isEmpty)
            const InlineEmpty(Icons.receipt_long_outlined, 'No transactions yet. Add one from the Home screen.')
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < recent.length && i < 15; i++) ...[
                    if (i > 0) const Divider(),
                    TransactionTile(
                      transaction: recent[i],
                      accounts: acctMap,
                      categories: cats,
                      onTap: () =>
                          openTransaction(context, ref, recent[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Balance ${Money.format(total)} = opening balance + money in - money out, from your transactions.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
