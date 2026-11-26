import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../domain/due_models.dart';
import 'due_widgets.dart';
import 'payment_sheet.dart';

/// Dues: "To receive" (expected income + lent) and "To pay" (borrowed).
class DuesPage extends ConsumerStatefulWidget {
  const DuesPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<DuesPage> createState() => _DuesPageState();
}

class _DuesPageState extends ConsumerState<DuesPage> {
  late int _tab = widget.initialTab;
  Set<DueStatus> _filter = {
    DueStatus.pending,
    DueStatus.partial,
    DueStatus.overdue,
  };

  Future<void> _openFilter() async {
    var selected = {..._filter};
    final result = await showModalBottomSheet<Set<DueStatus>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter by status',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in DueStatus.values)
                      FilterChip(
                        label: Text(statusLabel(s)),
                        selected: selected.contains(s),
                        onSelected: (on) => setSheet(
                          () => on ? selected.add(s) : selected.remove(s),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final views = ref.watch(dueViewsProvider).value ?? const <DueView>[];
    final people = {
      for (final p in ref.watch(peopleProvider).value ?? const <PeopleData>[])
        p.id: p,
    };
    final sources = {
      for (final s in ref.watch(sourcesProvider).value ?? const <IncomeSource>[])
        s.id: s,
    };
    final receivable = _tab == 0;
    final inTab = views.where((v) => v.isReceivable == receivable).toList();
    final total = inTab
        .where((v) => v.isOpen)
        .fold<int>(0, (s, v) => s + v.remaining);
    final overdueCount = inTab.where((v) => v.status == DueStatus.overdue).length;
    final shown = sortDues(inTab.where((v) => _filter.contains(v.status)));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hisaab',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          Text(
            'Dues',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              selectedBackgroundColor: context.accentFill,
              selectedForegroundColor: context.onAccent,
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('To receive')),
              ButtonSegment(value: 1, label: Text('To pay')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFilter,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Filter'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/people'),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('People'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: context.heroGradient,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receivable ? 'Total to receive' : 'Total to pay',
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Money.format(total),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: total == 0
                                ? Colors.white
                                : (receivable
                                      ? const Color(0xFF7DE3A0)
                                      : const Color(0xFFFF9A92)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (overdueCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x26FF9A92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$overdueCount overdue',
                      style: const TextStyle(
                        color: Color(0xFFFF9A92),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            SizedBox(
              height: 300,
              child: EmptyState(
                icon: receivable
                    ? Icons.south_west
                    : Icons.north_east,
                title: inTab.isEmpty
                    ? (receivable ? 'Nothing to receive' : 'Nothing to pay')
                    : 'Nothing matches the filter',
                message: receivable
                    ? 'Add money you are expecting or have lent, and Hisaab will remind you.'
                    : 'Add money you have borrowed, and Hisaab will remind you to pay it back.',
                actionLabel: receivable ? 'Add expected cash in' : 'Add borrowed money',
                onAction: () => context.push(
                  receivable ? '/dues/new/expected' : '/dues/new/borrowed',
                ),
              ),
            )
          else
            for (final v in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DueTile(
                  view: v,
                  people: people,
                  sources: sources,
                  onTap: () => context.push('/dues/${v.due.id}'),
                  onQuickReceive:
                      v.due.kind.name == 'expectedIncome' && v.isOpen
                      ? () => showPaymentSheet(context, ref, v)
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}
