import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../domain/savings_logic.dart';

class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(accountsProvider).value ?? const <Account>[];
    final balances = LedgerService.accountTotals(
      ref.watch(sourceBalancesProvider).value ?? const {},
    );
    final savings = all
        .where((a) => a.type == AccountType.savings && !a.isArchived)
        .toList();
    final total = savings.fold<int>(0, (s, a) => s + (balances[a.id] ?? 0));

    Future<String?> chooseSavings(String title) async {
      if (savings.length == 1) return savings.first.id;
      final r = await showItemPicker<String>(
        context,
        title: title,
        items: [
          for (final a in savings)
            PickerItem(
              value: a.id,
              title: a.name,
              subtitle: Money.format(balances[a.id] ?? 0),
              iconKey: a.iconKey,
              color: Color(a.colorValue),
            ),
        ],
      );
      return r?.value;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Savings')),
      body: savings.isEmpty
          ? EmptyState(
              icon: Icons.savings_outlined,
              title: 'No savings yet',
              message:
                  'Create a savings account, set a goal, and move money into it.',
              actionLabel: 'Create savings account',
              onAction: () => context.push('/accounts/new?type=savings'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: context.heroGradient,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total saved',
                        style: TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Money.format(total),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final a in savings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GoalCard(account: a, balance: balances[a.id] ?? 0),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    final id = await chooseSavings('Add to which savings?');
                    if (id != null && context.mounted) {
                      context.push('/transaction/new/transfer?to=$id');
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add to savings'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final id = await chooseSavings('Withdraw from which savings?');
                    if (id != null && context.mounted) {
                      context.push('/transaction/new/transfer?from=$id');
                    }
                  },
                  icon: const Icon(Icons.north_east),
                  label: const Text('Withdraw'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => context.push('/accounts/new?type=savings'),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('New savings account'),
                ),
              ],
            ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.account, required this.balance});

  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final goal = account.goalAmount;
    final progress = savingsProgress(balance: balance, goal: goal);
    final left = savingsRemaining(balance: balance, goal: goal);
    final tint = Color(account.colorValue);
    return AppCard(
      onTap: () => context.push('/accounts/${account.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBox(iconKey: account.iconKey, color: tint, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      goal == null
                          ? Money.format(balance)
                          : '${Money.format(balance)} of ${Money.format(goal)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (goal != null)
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: progress >= 1 ? colors.positive : null,
                  ),
                ),
            ],
          ),
          if (goal != null) ...[
            const SizedBox(height: 14),
            SoftProgress(
              value: progress,
              color: progress >= 1 ? colors.positive : context.tone(tint),
              height: 10,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    left == 0 ? 'Goal reached' : '${Money.format(left)} to go',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: left == 0 ? colors.positive : null,
                    ),
                  ),
                ),
                if (account.goalDate != null)
                  Text(
                    'Goal date: ${DateFormat('d MMM y').format(account.goalDate!)}',
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton(
                onPressed: () => context.push('/accounts/${account.id}/edit'),
                child: const Text('Set a goal'),
              ),
            ),
        ],
      ),
    );
  }
}
