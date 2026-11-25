import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../data/notification_coordinator.dart';

/// Reminders whose time has passed and that the user has not dealt with.
/// Re-checked every 30 seconds so a reminder moves here when its time comes.
final missedNotificationsProvider =
    StreamProvider.autoDispose<List<NotificationLogData>>((ref) {
      final repo = ref.watch(notificationLogRepositoryProvider);
      final controller = StreamController<List<NotificationLogData>>();
      var latest = const <NotificationLogData>[];
      void emit() {
        if (controller.isClosed) return;
        final now = DateTime.now();
        controller.add([
          for (final r in latest)
            if (!r.fireAt.isAfter(now)) r,
        ]);
      }

      final sub = repo.watchUnhandled().listen((rows) {
        latest = rows;
        emit();
      });
      final timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
      ref.onDispose(() {
        timer.cancel();
        sub.cancel();
        controller.close();
      });
      return controller.stream;
    });

/// Number for the bell badge.
final missedCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(missedNotificationsProvider).value?.length ?? 0,
);

String agoLabel(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(at);
}

IconData iconForType(String type) => switch (type) {
  'payday' => Icons.payments_outlined,
  'expectedFollowUp' => Icons.hourglass_bottom,
  'owe' => Icons.north_east,
  'owed' => Icons.south_west,
  'subscription' => Icons.autorenew,
  'overdue' => Icons.warning_amber_rounded,
  'backup' => Icons.cloud_upload_outlined,
  _ => Icons.notifications_none,
};

class MissedPage extends ConsumerWidget {
  const MissedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missed = ref.watch(missedNotificationsProvider);
    final rows = missed.value ?? const <NotificationLogData>[];
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Missed reminders'),
        actions: [
          if (rows.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Clear all?',
                  message:
                      'Marks all ${rows.length} reminders as done. The bills and dues themselves are not changed.',
                  confirmLabel: 'Clear all',
                );
                if (ok) {
                  await ref
                      .read(notificationLogRepositoryProvider)
                      .handleAllMissed();
                }
              },
              child: const Text('Clear all'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 56,
                      color: context.appColors.positive,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'All caught up',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Reminders you did not respond to will wait here, so nothing slips by.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _MissedCard(row: rows[i], now: now),
            ),
    );
  }
}

class _MissedCard extends ConsumerWidget {
  const _MissedCard({required this.row, required this.now});

  final NotificationLogData row;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.read(notificationLogRepositoryProvider);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconForType(row.type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (row.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          row.body,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      agoLabel(row.fireAt, now),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () async {
                      await repo.handleByKey(row.key);
                      if (context.mounted) {
                        context.push(await ref.read(notificationCoordinatorProvider).resolveRoute(row.payload, null));
                      }
                    },
                    child: const Text('Open'),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: () async {
                    await ref.read(notificationCoordinatorProvider).snooze(row);
                    if (context.mounted) {
                      showMessage(context, 'Will remind you again in 1 hour.');
                    }
                  },
                  child: const Text('In 1 hour'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: () => repo.handleByKey(row.key),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
