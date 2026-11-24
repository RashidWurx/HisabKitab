import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/detail_widgets.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/period.dart';
import '../../ledger/data/ledger_service.dart';
import 'source_form_page.dart';
import 'sources_page.dart';

class SourceDetailPage extends ConsumerStatefulWidget {
  const SourceDetailPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends ConsumerState<SourceDetailPage> {
  PeriodKind _period = PeriodKind.thisMonth;

  @override
  Widget build(BuildContext context) {
    final id = widget.sourceId;
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    IncomeSource? source;
    for (final s in sources) {
      if (s.id == id) source = s;
    }
    if (source == null) {
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
    final balances = ref.watch(sourceBalancesProvider).value ?? const {};
    final where =
        balances.entries
            .where((e) => e.key.sourceId == id && e.value != 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final totalLeft = LedgerService.sourceTotals(balances)[id] ?? 0;
    final range = rangeFor(_period, monthStartDay: monthStartDayOf(ref));
    final stats = ref.watch(sourceStatsProvider((id, range))).value;
    final spend =
        ref.watch(spendingByCategoryProvider((range, null, id))).value ??
        const [];
    final linkedName = accounts[source.linkedAccountId]?.name;
    final schedule = source.payScheduleType == null
        ? 'None'
        : scheduleLabels[source.payScheduleType]!;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(sourceRepositoryProvider);
              if (v == 'edit') {
                context.push('/sources/$id/edit');
              } else if (v == 'archive') {
                await repo.setArchived(id, !source!.isArchived);
              } else if (v == 'delete') {
                await deleteSourceFlow(context, ref, id);
                if (!context.mounted) return;
                if (await repo.get(id) == null && context.mounted) {
                  context.pop();
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!source!.isBuiltIn) ...[
                PopupMenuItem(
                  value: 'archive',
                  child: Text(source.isArchived ? 'Unarchive' : 'Archive'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Row(
            children: [
              IconBox(
                iconKey: source.iconKey,
                color: Color(source.colorValue),
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  source.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (source.status == ActiveStatus.inactive)
                const StatusChip('Inactive'),
            ],
          ),
          const SizedBox(height: 12),
          if (!source.isBuiltIn)
            Wrap(
              spacing: 16,
              children: [
                Text('Linked account: ${linkedName ?? 'None'}'),
                Text('Schedule: $schedule'),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'This period',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              PeriodMenu(
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: _stat(
                    'Received',
                    MoneyText(
                      stats?.received ?? 0,
                      neutral: (stats?.received ?? 0) == 0,
                      style: _big,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _stat(
                    'Spent',
                    MoneyText(-(stats?.spent ?? 0), style: _big),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: InfoRow(
              'Left now (all accounts)',
              null,
              valueWidget: MoneyText(
                totalLeft,
                neutral: totalLeft >= 0,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SectionTitle('Where your money is'),
          if (where.isEmpty)
            const Text('No money from this source is sitting anywhere.')
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < where.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      leading: IconBox(
                        iconKey: accounts[where[i].key.accountId]?.iconKey ?? 'bank',
                        size: 36,
                      ),
                      title: Text(
                        accounts[where[i].key.accountId]?.name ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            where[i].value,
                            neutral: where[i].value >= 0,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () =>
                          context.push('/accounts/${where[i].key.accountId}'),
                    ),
                  ],
                ],
              ),
            ),
          const SectionTitle('Spending by category'),
          CategoryBars(spend: spend, categories: cats),
          if (!source.isBuiltIn) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive sources get no payday reminders'),
              value: source.status == ActiveStatus.active,
              onChanged: (v) => ref
                  .read(sourceRepositoryProvider)
                  .setStatus(
                    id,
                    v ? ActiveStatus.active : ActiveStatus.inactive,
                  ),
            ),
          ],
          if (source.note != null && source.note!.isNotEmpty) ...[
            const SectionTitle('Note'),
            Text(source.note!),
          ],
        ],
      ),
    );
  }

  static const _big = TextStyle(fontSize: 22, fontWeight: FontWeight.w800);

  Widget _stat(String label, Widget value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(label, style: const TextStyle(fontSize: 15)), value],
  );
}
