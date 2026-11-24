import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../domain/transaction_models.dart';

/// "Split by source" sheet. Returns the confirmed allocations, or null.
Future<List<AllocationInput>?> showSplitSheet(
  BuildContext context, {
  required int amount,
  required List<AllocationInput> initial,
  required Map<String, int> balancesInAccount,
  String title = 'Expense amount',
}) {
  return showModalBottomSheet<List<AllocationInput>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SplitSheet(
      amount: amount,
      initial: initial,
      balancesInAccount: balancesInAccount,
      title: title,
    ),
  );
}

class _Row {
  _Row(this.sourceId, int paisa)
    : controller = TextEditingController(
        text: paisa == 0
            ? ''
            : Money.format(paisa).replaceFirst('Rs ', '').replaceAll(',', ''),
      );
  String sourceId;
  final TextEditingController controller;
}

class _SplitSheet extends ConsumerStatefulWidget {
  const _SplitSheet({
    required this.amount,
    required this.initial,
    required this.balancesInAccount,
    required this.title,
  });

  final int amount;
  final List<AllocationInput> initial;
  final Map<String, int> balancesInAccount;
  final String title;

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  late final List<_Row> _rows = [
    for (final a in widget.initial) _Row(a.sourceId, a.amount),
  ];

  List<AllocationInput> get _allocations => [
    for (final r in _rows)
      AllocationInput(r.sourceId, parseAmount(r.controller.text) ?? 0),
  ];

  int get _allocated => _allocations.fold(0, (s, a) => s + a.amount);

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  String _name(List<IncomeSource> sources, String id) {
    for (final s in sources) {
      if (s.id == id) return s.name;
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final colors = context.appColors;
    final left = widget.amount - _allocated;
    final allocations = _allocations;
    final valid =
        left == 0 && allocations.every((a) => a.amount > 0) && _rows.isNotEmpty;
    final shades = [
      AppTheme.navy,
      AppTheme.navyMid,
      AppTheme.navySoft,
      const Color(0xFF8FA6BF),
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Split by source',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(
              Money.format(widget.amount),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    for (var i = 0; i < allocations.length; i++)
                      if (allocations[i].amount > 0 && widget.amount > 0)
                        Expanded(
                          flex: allocations[i].amount,
                          child: Container(
                            color: shades[i % shades.length],
                            alignment: Alignment.center,
                            child: Text(
                              '${(allocations[i].amount * 100 / widget.amount).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    if (left > 0)
                      Expanded(
                        flex: left,
                        child: Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InfoRow('Allocated', Money.format(_allocated)),
            InfoRow(
              'Left to allocate',
              null,
              valueWidget: MoneyText(
                left,
                neutral: left == 0,
                forceColor: left == 0
                    ? null
                    : (left < 0 ? colors.negative : colors.pending),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SectionTitle('Allocations'),
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.sell_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final r = await pickSource(
                              context,
                              ref,
                              selectedId: row.sourceId,
                              balances: widget.balancesInAccount,
                              exclude: {
                                for (final o in _rows)
                                  if (o != row) o.sourceId,
                              },
                            );
                            if (r?.value != null) {
                              setState(() => row.sourceId = r!.value!);
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name(sources, row.sourceId),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Here: ${Money.format(widget.balancesInAccount[row.sourceId] ?? 0)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: row.controller,
                          onChanged: (_) => setState(() {}),
                          textAlign: TextAlign.end,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ), inputFormatters: amountFormatters,
                          decoration: const InputDecoration(
                            prefixText: 'Rs ',
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          row.controller.dispose();
                          _rows.remove(row);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () async {
                final r = await pickSource(
                  context,
                  ref,
                  balances: widget.balancesInAccount,
                  exclude: {for (final o in _rows) o.sourceId},
                );
                if (r?.value != null) {
                  setState(() => _rows.add(_Row(r!.value!, left > 0 ? left : 0)));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add source'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(context, allocations) : null,
              child: const Text('Confirm split'),
            ),
          ],
        ),
      ),
    );
  }
}
