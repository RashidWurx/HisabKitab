import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../dues/presentation/due_widgets.dart';
import '../../transactions/presentation/transaction_tile.dart';
import '../domain/subscription_logic.dart';
import 'subscription_pay_sheet.dart';
import 'subscriptions_page.dart' show DueTone, dueCountdown;

class SubscriptionDetailPage extends ConsumerWidget {
  const SubscriptionDetailPage({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = (ref.watch(subscriptionsProvider).value ?? const <Subscription>[])
        .where((s) => s.id == subscriptionId)
        .firstOrNull;
    if (sub == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final accounts = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };
    final cats = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };
    final spend = ref.watch(subscriptionSpendProvider(subscriptionId)).value;
    final payments =
        ref.watch(subscriptionPaymentsProvider(subscriptionId)).value ??
        const [];
    final repo = ref.read(subscriptionRepositoryProvider);
    final active = sub.status == SubscriptionStatus.active;
    final countdown = dueCountdown(sub.nextDueDate);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  context.push('/subscriptions/$subscriptionId/edit');
                case 'pause':
                  await repo.setStatus(
                    subscriptionId,
                    active ? SubscriptionStatus.paused : SubscriptionStatus.active,
                  );
                case 'cancel':
                  await repo.setStatus(subscriptionId, SubscriptionStatus.cancelled);
                case 'delete':
                  final ok = await confirmDialog(
                    context,
                    title: 'Delete subscription?',
                    message:
                        'Your recorded payments stay in Activity. Only the subscription is removed.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (ok) {
                    await repo.delete(subscriptionId);
                    if (context.mounted) context.pop();
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'pause',
                child: Text(active ? 'Pause' : 'Resume'),
              ),
              if (sub.status != SubscriptionStatus.cancelled)
                const PopupMenuItem(value: 'cancel', child: Text('Cancel subscription')),
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
              InitialsAvatar(sub.name, size: 64, color: AppTheme.navyMid),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${Money.format(sub.amount)} / ${billingLabel(sub.billingUnit, sub.billingEvery)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              if (!active)
                StatusChip(
                  sub.status == SubscriptionStatus.paused ? 'Paused' : 'Cancelled',
                ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                InfoRow('Next renewal', formatDate(sub.nextDueDate)),
                if (active) ...[
                  const Divider(),
                  InfoRow(
                    'Status',
                    null,
                    valueWidget: Text(
                      countdown.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: switch (countdown.tone) {
                          DueTone.late => colors.negative,
                          DueTone.soon => colors.pending,
                          DueTone.calm => null,
                        },
                      ),
                    ),
                  ),
                ],
                const Divider(),
                InfoRow('Paid from', accounts[sub.accountId]?.name ?? '-'),
                const Divider(),
                InfoRow(
                  'Monthly cost',
                  Money.format(
                    monthlyCost(
                      amount: sub.amount,
                      unit: sub.billingUnit,
                      every: sub.billingEvery,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Spent'),
          Row(
            children: [
              Expanded(child: _spendCard('This month', spend?.thisMonth ?? 0)),
              const SizedBox(width: 10),
              Expanded(child: _spendCard('This year', spend?.thisYear ?? 0)),
              const SizedBox(width: 10),
              Expanded(child: _spendCard('All time', spend?.allTime ?? 0)),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showSubscriptionPaySheet(context, ref, sub),
              child: const Text('Mark paid'),
            ),
          ],
          const SectionTitle('Payment history'),
          if (payments.isEmpty)
            const AppCard(child: Text('No payments recorded yet.'))
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < payments.length; i++) ...[
                    if (i > 0) const Divider(),
                    TransactionTile(
                      transaction: payments[i],
                      accounts: accounts,
                      categories: cats,
                      onTap: () => context.push('/transaction/${payments[i].id}/edit'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _spendCard(String label, int paisa) => AppCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            -paisa,
            neutral: paisa == 0,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
