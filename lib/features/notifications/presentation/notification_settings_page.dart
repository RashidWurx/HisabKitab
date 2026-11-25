import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/ui/widgets.dart';
import '../data/notification_coordinator.dart';
import '../domain/notification_models.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool? _allowed;
  bool? _exact;
  int _pending = 0;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    ref.read(reminderSchedulerProvider).stopPreview();
    super.dispose();
  }

  Future<void> _refresh() async {
    final scheduler = ref.read(reminderSchedulerProvider);
    final allowed = await scheduler.areNotificationsEnabled();
    final pending = await scheduler.pendingCount();
    final exact = await scheduler.canScheduleExact();
    if (mounted) {
      setState(() {
        _allowed = allowed;
        _pending = pending;
        _exact = exact;
      });
    }
  }

  Future<void> _pickSound(SoundPrefs sound) async {
    final scheduler = ref.read(reminderSchedulerProvider);
    final picked = await scheduler.pickRingtone(sound.uri);
    if (picked == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.set(SoundPrefs.uriKey, picked.uri);
    await repo.set(SoundPrefs.titleKey, picked.title);
  }

  Future<void> _togglePreview(SoundPrefs sound) async {
    final scheduler = ref.read(reminderSchedulerProvider);
    if (_previewing) {
      await scheduler.stopPreview();
      setState(() => _previewing = false);
    } else {
      await scheduler.previewSound(sound.uri, alarm: sound.alarmStream);
      setState(() => _previewing = true);
    }
  }

  Future<void> _setField(NotificationType t, String field, String value) =>
      ref
          .read(settingsRepositoryProvider)
          .set(NotificationPrefs.keyOf(t, field), value);

  String _timeLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickTime(NotificationType t, TypePrefs p) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.minutes ~/ 60, minute: p.minutes % 60),
    );
    if (picked != null) {
      await _setField(t, 'minutes', '${picked.hour * 60 + picked.minute}');
    }
  }

  Future<void> _pickDays(NotificationType t, TypePrefs p) async {
    final label = daysLabel(t)!;
    final text = await showTextDialog(
      context,
      title: label,
      initial: '${p.days}',
      confirmLabel: 'Save',
    );
    final n = int.tryParse(text?.trim() ?? '');
    if (n != null && n >= 0 && n <= 365) {
      await _setField(t, 'days', '$n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final prefs = settings?.notificationPrefs ?? NotificationPrefs.defaults;
    final scheduler = ref.read(reminderSchedulerProvider);
    final scheme = Theme.of(context).colorScheme;
    final sound = settings?.soundPrefs ?? SoundPrefs.defaults;
    final repo = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _allowed == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _allowed == null
                            ? 'Checking…'
                            : _allowed!
                            ? 'Notifications are allowed'
                            : 'Notifications are off for Hisaab',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$_pending reminder${_pending == 1 ? '' : 's'} scheduled on this phone (the nearest 60 are kept).',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () async {
                    await ref.read(notificationCoordinatorProvider).scheduleTest();
                    if (context.mounted) {
                      showMessage(context, 'A test reminder will arrive in 1 minute.');
                    }
                  },
                  child: const Text('Send a test in 1 minute'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_allowed != true)
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          onPressed: () async {
                            await scheduler.requestPermission();
                            await ref
                                .read(notificationCoordinatorProvider)
                                .reschedule();
                            await _refresh();
                          },
                          child: const Text('Allow notifications'),
                        ),
                      ),
                    if (_allowed != true) const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: () async {
                          await ref.read(notificationCoordinatorProvider).reschedule();
                          await scheduler.showTest();
                        },
                        child: const Text('Send a test'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Sound'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reminder sound',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _pickSound(sound),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.music_note_outlined, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  sound.uri == null
                                      ? 'Phone default'
                                      : (sound.title ?? 'Custom ringtone'),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: _previewing ? 'Stop' : 'Play',
                      onPressed: () => _togglePreview(sound),
                      icon: Icon(_previewing ? Icons.stop : Icons.play_arrow),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Loud (alarm volume)'),
                  subtitle: const Text(
                    'Uses the alarm volume, so reminders are heard even when the phone is quiet.',
                  ),
                  value: sound.alarmStream,
                  onChanged: (v) => repo.setBool(SoundPrefs.alarmKey, v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep ringing until I respond'),
                  subtitle: const Text(
                    'The sound repeats until you open or dismiss the reminder.',
                  ),
                  value: sound.keepRinging,
                  onChanged: (v) => repo.setBool(SoundPrefs.ringingKey, v),
                ),
              ],
            ),
          ),
          const SectionTitle('Reliable delivery'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _exact == true
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: _exact == true ? null : Colors.orange,
                  ),
                  title: Text(
                    _exact == true
                        ? 'Exact timing is on'
                        : 'Exact timing is off',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _exact == true
                        ? 'Reminders fire at the minute, even when the phone is idle.'
                        : 'Allow "Alarms & reminders" so reminders are not delayed.',
                  ),
                  trailing: _exact == true
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await scheduler.requestExactAlarms();
                            await _refresh();
                          },
                          child: const Text('Allow'),
                        ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: const Text(
                    'Run without battery limits',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Lets reminders arrive when the app is closed.',
                  ),
                  trailing: TextButton(
                    onPressed: scheduler.requestIgnoreBatteryOptimisation,
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Not arriving when the app is closed?'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Some phones (TECNO, Infinix, Xiaomi, Oppo, Vivo and others) stop apps in the background to save battery, which can silence reminders. Set Hisaab to "No restrictions" / "Allow background activity", and turn on Autostart if your phone has it.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: scheduler.openAppSettings,
                        child: const Text('App settings'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: scheduler.openBatterySettings,
                        child: const Text('Battery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Then use "Send a test in 1 minute", close the app and wait: it should still arrive.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),          const SectionTitle('Reminder types'),
          for (final t in NotificationType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TypeCard(
                type: t,
                prefs: prefs.of(t),
                timeLabel: _timeLabel(prefs.of(t).minutes),
                onToggle: (v) => _setField(t, 'enabled', v ? '1' : '0'),
                onTime: () => _pickTime(t, prefs.of(t)),
                onDays: daysLabel(t) == null
                    ? null
                    : () => _pickDays(t, prefs.of(t)),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Each due, subscription or reminder can also have its own date and time, which replaces these defaults.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.prefs,
    required this.timeLabel,
    required this.onToggle,
    required this.onTime,
    required this.onDays,
  });

  final NotificationType type;
  final TypePrefs prefs;
  final String timeLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTime;
  final VoidCallback? onDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = daysLabel(type);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  notificationTypeLabels[type]!,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Switch(value: prefs.enabled, onChanged: onToggle),
            ],
          ),
          if (prefs.enabled)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Row(
                children: [
                  if (type != NotificationType.custom)
                    Expanded(
                      child: _chip(
                        context,
                        Icons.schedule,
                        timeLabel,
                        onTime,
                      ),
                    ),
                  if (type != NotificationType.custom && label != null)
                    const SizedBox(width: 8),
                  if (label != null)
                    Expanded(
                      flex: 2,
                      child: _chip(
                        context,
                        Icons.event_outlined,
                        '${prefs.days} · ${label.split(' (').first}',
                        onDays!,
                      ),
                    ),
                  if (type == NotificationType.custom)
                    Expanded(
                      child: Text(
                        'Uses the date and time of each reminder.',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String text,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
