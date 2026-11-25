import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../notifications/presentation/missed_page.dart';

class _Item {
  const _Item(this.icon, this.title, this.subtitle, this.route, {this.badge = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool badge;
}

const _groups = <(String, List<_Item>)>[
  (
    'Your money',
    [
      _Item(Icons.account_balance_wallet_outlined, 'Accounts', 'Bank, cash and wallets', '/accounts'),
      _Item(Icons.toll_outlined, 'Income sources', 'Where your money comes from', '/sources'),
      _Item(Icons.sell_outlined, 'Categories', 'Where your money goes', '/categories'),
      _Item(Icons.people_outline, 'People', 'Who owes what', '/people'),
      _Item(Icons.track_changes, 'Savings', 'Goals and set-aside money', '/savings'),
    ],
  ),
  (
    'Reminders',
    [
      _Item(Icons.notifications_active_outlined, 'Missed reminders', 'Everything you have not dealt with', '/notifications', badge: true),
      _Item(Icons.notifications_none, 'Custom reminders', 'Your own repeating reminders', '/reminders'),
    ],
  ),
  (
    'App',
    [
      _Item(Icons.settings_outlined, 'Settings', 'Sound, lock, months, appearance', '/settings'),
      _Item(Icons.cloud_upload_outlined, 'Backup & restore', 'Keep your data safe', '/backup'),
    ],
  ),
];

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final missed = ref.watch(missedCountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          for (final (title, items) in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(indent: 72, height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(items[i].icon, color: scheme.primary),
                      ),
                      title: Text(
                        items[i].title,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(items[i].subtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (items[i].badge && missed > 0)
                            Badge(label: Text('$missed'), backgroundColor: scheme.error),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => context.push(items[i].route),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
