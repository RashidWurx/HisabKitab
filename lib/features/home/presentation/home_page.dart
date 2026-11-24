import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';

/// Basic Home: total balance and the accounts list.
/// The full dashboard (period cards, money by source, charts) is Phase 3.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final balances = LedgerService.accountTotals(
      ref.watch(sourceBalancesProvider).value ?? const {},
    );
    final totals = LedgerService.headlineTotals(accounts, balances);
    final visible = accounts.where((a) => !a.isArchived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hisaab',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
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
                Text(
                  Money.format(totals.total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Includes ${Money.format(totals.savings)} in savings',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
          SectionTitle(
            'Accounts',
            trailing: TextButton(
              onPressed: () => context.push('/accounts'),
              child: const Text('Manage'),
            ),
          ),
          if (visible.isEmpty)
            SizedBox(
              height: 260,
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
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      leading: IconBox(
                        iconKey: visible[i].iconKey,
                        color: Color(visible[i].colorValue),
                        size: 40,
                      ),
                      title: Text(
                        visible[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: MoneyText(
                        balances[visible[i].id] ?? 0,
                        neutral: (balances[visible[i].id] ?? 0) >= 0,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => context.push('/accounts/${visible[i].id}'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
