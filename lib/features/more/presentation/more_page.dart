import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/widgets.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.account_balance_wallet_outlined, 'Accounts', () => context.push('/accounts')),
      (Icons.toll_outlined, 'Income sources', () => context.push('/sources')),
      (Icons.sell_outlined, 'Categories', () => context.push('/categories')),
      (Icons.people_outline, 'People', () => context.push('/people')),
      (Icons.track_changes, 'Savings', () => context.push('/savings')),
      (Icons.notifications_none, 'Custom reminders', () => context.push('/reminders')),
      (Icons.settings_outlined, 'Settings', () => context.push('/settings')),
      (Icons.cloud_upload_outlined, 'Backup & restore', () => context.push('/backup')),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Hisaab')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('More'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  ListTile(
                    leading: Icon(items[i].$1, size: 28),
                    title: Text(
                      items[i].$2,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: items[i].$3,
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
