import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../data/settings_repository.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final repo = ref.read(settingsRepositoryProvider);
    if (settings == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('Spending'),
          Card(
            child: SwitchListTile(
              title: const Text('Ask which source on every expense'),
              subtitle: const Text(
                'When off, the source is picked automatically and the picker is hidden.',
              ),
              value: settings.askSourceEachExpense,
              onChanged: (v) =>
                  repo.setBool(SettingKeys.askSourceEachExpense, v),
            ),
          ),
          const SectionTitle('Months'),
          AppCard(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Month starts on day',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                DropdownButton<int>(
                  value: settings.monthStartDay.clamp(1, 28),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var d = 1; d <= 28; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) =>
                      repo.set(SettingKeys.monthStartDay, '${v ?? 1}'),
                ),
              ],
            ),
          ),
          const SectionTitle('Appearance'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System')),
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => repo.set(SettingKeys.themeMode, s.first),
          ),
          const SectionTitle('Setup'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Run setup again'),
              subtitle: const Text('Add accounts, sources and categories'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/onboarding'),
            ),
          ),
          const SectionTitle('Danger zone'),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: context.appColors.negative,
              ),
              title: Text(
                'Delete all data',
                style: TextStyle(
                  color: context.appColors.negative,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text('Removes everything on this phone'),
              onTap: () => _deleteAll(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final first = await confirmDialog(
      context,
      title: 'Delete all data?',
      message:
          'All accounts, sources, transactions and settings on this phone will be erased. This cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!first || !context.mounted) return;
    final controller = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type DELETE to confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              controller.text.trim().toUpperCase() == 'DELETE',
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (second != true) return;
    await ref.read(settingsRepositoryProvider).deleteAllData();
    // Onboarding flag is gone, so the router sends the user back to setup.
  }
}
