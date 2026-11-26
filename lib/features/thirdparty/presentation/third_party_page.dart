import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../domain/pass_models.dart';
import 'pass_widgets.dart';

/// 3rd party money: everything open, then everything finished.
class ThirdPartyPage extends ConsumerWidget {
  const ThirdPartyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(passViewsProvider).value ?? const <PassView>[];
    final summary = ref.watch(passSummaryProvider);
    final people = ref.watch(peopleProvider).value ?? const <PeopleData>[];
    final open = views.where((v) => v.isOpen).toList();
    final done = views.where((v) => !v.isOpen).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('3rd party money')),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        heroTag: 'add-pass',
        onPressed: () => context.push('/third-party/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: views.isEmpty
          ? EmptyState(
              icon: Icons.sync_alt,
              title: 'Nothing here yet',
              message:
                  'Borrowed money from one person for another? Track it here. It is never counted as your income or expense.',
              actionLabel: 'Add record',
              onAction: () => context.push('/third-party/new'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: [
                AppCard(
                  child: Column(
                    children: [
                      InfoRow(
                        'To collect',
                        null,
                        valueWidget: MoneyText(summary.toCollect, style: _big),
                      ),
                      const Divider(),
                      InfoRow(
                        'To return',
                        null,
                        valueWidget: MoneyText(-summary.toPayBack, style: _big),
                      ),
                    ],
                  ),
                ),
                if (open.isNotEmpty) ...[
                  const SectionTitle('Open'),
                  for (final v in open) _PassTile(v, PassNames.of(v, people)),
                ],
                if (done.isNotEmpty) ...[
                  const SectionTitle('Completed'),
                  for (final v in done) _PassTile(v, PassNames.of(v, people)),
                ],
              ],
            ),
    );
  }
}

const _big = TextStyle(fontSize: 18, fontWeight: FontWeight.w800);

class _PassTile extends StatelessWidget {
  const _PassTile(this.view, this.names);

  final PassView view;
  final PassNames names;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final now = DateTime.now();
    final overdue = v.collectOverdue(now) || v.payBackOverdue(now);
    final lines = [
      if (v.toHandOver > 0)
        'Still to give ${names.receiver}: ${Money.format(v.toHandOver)}',
      if (v.toCollect > 0)
        'Collect ${Money.format(v.toCollect)} from ${names.receiver}',
      if (v.toPayBack > 0)
        'Return ${Money.format(v.toPayBack)} to ${names.lender}',
      if (!v.isOpen) 'Completed',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => context.push('/third-party/${v.pass.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${names.lender} → ${names.receiver}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (overdue) StatusChip('Overdue', color: colors.negative),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${Money.format(v.amount)} · ${DateFormat('d MMM y').format(v.pass.startDate)}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}
