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
import '../domain/subscription_logic.dart';
import 'subscription_pay_sheet.dart';

const subscriptionIdeas = ['Spotify', 'Google One', 'iCloud', 'VPS', 'Warehouse'];

/// "Due in 3 days" / "Due today" / "Overdue by 2 days".
({String text, DueTone tone}) dueCountdown(DateTime due, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final days = DateUtils.dateOnly(due).difference(today).inDays;
  if (days < 0) {
    return (text: 'Overdue by ${-days} day${days == -1 ? '' : 's'}', tone: DueTone.late);
  }
  if (days == 0) return (text: 'Due today', tone: DueTone.soon);
  if (days == 1) return (text: 'Due tomorrow', tone: DueTone.soon);
  if (days <= 7) return (text: 'Due in $days days', tone: DueTone.soon);
  return (text: 'Due ${formatDateShort(due)}', tone: DueTone.calm);
}

enum DueTone { late, soon, calm }

class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(subscriptionsProvider).value ?? const <Subscription>[];
    final spend = ref.watch(subscriptionSpendProvider(null)).value;
    final accounts = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };
    final active = all.where((s) => s.status == SubscriptionStatus.active).toList();
    final inactive = all.where((s) => s.status != SubscriptionStatus.active).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        toolbarHeight: 64,
        title: const Text(
          'Hisaab',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -0.6),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        heroTag: 'add-subscription',
        onPressed: () => context.push('/subscriptions/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 128),
        children: [
          Text(
            'Subscriptions',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Monthly cost',
                  value: Money.format(totalMonthlyCost(all)),
                  icon: Icons.autorenew,
                  dark: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Paid this month',
                  value: Money.format(spend?.thisMonth ?? 0),
                  icon: Icons.check_circle_outline,
                ),
              ),
            ],
          ),
          if (all.isEmpty) ...[
            const SizedBox(height: 24),
            _EmptyHints(),
          ] else ...[
            const SectionTitle('Next renewals'),
            if (active.isEmpty)
              const AppCard(child: Text('No active subscriptions.'))
            else
              for (final s in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SubscriptionTile(
                    sub: s,
                    account: accounts[s.accountId],
                  ),
                ),
            if (inactive.isNotEmpty) ...[
              const SectionTitle('Paused and cancelled'),
              for (final s in inactive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SubscriptionTile(
                    sub: s,
                    account: accounts[s.accountId],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.dark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : null;
    final sub = dark ? const Color(0xB3FFFFFF) : Theme.of(context).colorScheme.onSurfaceVariant;
    final child = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: sub),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, color: sub)),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    if (!dark) return AppCard(padding: EdgeInsets.zero, child: child);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D4068), AppTheme.navy],
        ),
      ),
      child: child,
    );
  }
}

class _EmptyHints extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.autorenew, size: 56),
        const SizedBox(height: 12),
        Text(
          'Track what renews',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Add your subscriptions and Hisaab will remind you before each renewal.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final idea in subscriptionIdeas)
              ActionChip(
                label: Text(idea),
                onPressed: () => context.push('/subscriptions/new?name=$idea'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
          onPressed: () => context.push('/subscriptions/new'),
          child: const Text('Add subscription'),
        ),
      ],
    );
  }
}

class SubscriptionTile extends ConsumerWidget {
  const SubscriptionTile({super.key, required this.sub, this.account});

  final Subscription sub;
  final Account? account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final active = sub.status == SubscriptionStatus.active;
    final countdown = dueCountdown(sub.nextDueDate);
    final toneColor = switch (countdown.tone) {
      DueTone.late => colors.negative,
      DueTone.soon => colors.pending,
      DueTone.calm => scheme.onSurfaceVariant,
    };
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/subscriptions/${sub.id}'),
      child: Row(
        children: [
          InitialsAvatar(sub.name, size: 46, color: AppTheme.navyMid),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${Money.format(sub.amount)} / ${billingLabel(sub.billingUnit, sub.billingEvery)}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                active
                    ? Text(
                        countdown.text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: toneColor,
                        ),
                      )
                    : StatusChip(
                        sub.status == SubscriptionStatus.paused ? 'Paused' : 'Cancelled',
                        color: scheme.outline,
                      ),
              ],
            ),
          ),
          if (active)
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => showSubscriptionPaySheet(context, ref, sub),
              child: const Text('Pay'),
            ),
        ],
      ),
    );
  }
}
