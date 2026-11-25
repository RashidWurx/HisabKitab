import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../applock/application/app_lock_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../data/settings_repository.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final repo = ref.read(settingsRepositoryProvider);
    final lock = ref.watch(appLockProvider).config;
    if (settings == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const _Heading('Reminders & security'),
          _Group(
            children: [
              _NavTile(
                icon: Icons.notifications_active_outlined,
                title: 'Notifications',
                subtitle: 'Sound, loudness, what to remind you about',
                onTap: () => context.push('/settings/notifications'),
              ),
              _NavTile(
                icon: Icons.lock_outline,
                title: 'App lock',
                subtitle: lock.enabled
                    ? (lock.biometrics ? 'On, PIN and fingerprint' : 'On, PIN')
                    : 'Off',
                onTap: () => context.push('/settings/app-lock'),
              ),
            ],
          ),
          const _Heading('How the app works'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const _IconTile(Icons.tune),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: const _TileTitle('Ask which source on every expense'),
                subtitle: const Text(
                  'When off, the source is picked automatically and the picker is hidden.',
                ),
                value: settings.askSourceEachExpense,
                onChanged: (v) =>
                    repo.setBool(SettingKeys.askSourceEachExpense, v),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const _IconTile(Icons.calendar_month_outlined),
                title: const _TileTitle('Month starts on day'),
                subtitle: const Text('For people paid on a day other than the 1st'),
                trailing: DropdownButton<int>(
                  value: settings.monthStartDay.clamp(1, 28),
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var d = 1; d <= 28; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) =>
                      repo.set(SettingKeys.monthStartDay, '${v ?? 1}'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _IconTile(Icons.brightness_6_outlined),
                        SizedBox(width: 16),
                        _TileTitle('Appearance'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('System')),
                          ButtonSegment(value: 'light', label: Text('Light')),
                          ButtonSegment(value: 'dark', label: Text('Dark')),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) =>
                            repo.set(SettingKeys.themeMode, s.first),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Heading('Your data'),
          _Group(
            children: [
              _NavTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Backup & restore',
                subtitle: 'Keep a copy safe, or move to a new phone',
                onTap: () => context.push('/backup'),
              ),
              _NavTile(
                icon: Icons.restart_alt,
                title: 'Run setup again',
                subtitle: 'Add accounts, sources and categories',
                onTap: () => context.push('/onboarding'),
              ),
            ],
          ),
          const _Heading('Danger zone'),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: context.appColors.negative.withValues(alpha: 0.35),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.appColors.negative.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.delete_forever_outlined,
                  color: context.appColors.negative,
                ),
              ),
              title: Text(
                'Delete all data',
                style: TextStyle(
                  fontSize: 16.5,
                  color: context.appColors.negative,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text('Removes everything on this phone'),
              onTap: () => _deleteAll(context, ref),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Hisaab · works fully offline',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
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
    final typed = await showTextDialog(
      context,
      title: 'Are you absolutely sure?',
      hint: 'Type DELETE to confirm',
      confirmLabel: 'Delete everything',
      capitalization: TextCapitalization.characters,
    );
    if (typed == null || typed.trim().toUpperCase() != 'DELETE') return;
    await ref.read(settingsRepositoryProvider).deleteAllData();
    await ref.read(appLockProvider.notifier).disable(); // forget the PIN too
    // Onboarding flag is gone, so the router sends the user back to setup.
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: 72, height: 1),
          children[i],
        ],
      ],
    ),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: scheme.primary),
    );
  }
}

class _TileTitle extends StatelessWidget {
  const _TileTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
  );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: _IconTile(icon),
    title: _TileTitle(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
