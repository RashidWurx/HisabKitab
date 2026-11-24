import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/seed.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../domain/transaction_models.dart';
import 'split_sheet.dart';

/// Which source's money is involved: one source, or a split.
class AllocationChoice {
  const AllocationChoice({this.sourceId, this.split});

  final String? sourceId;
  final List<AllocationInput>? split;

  static const none = AllocationChoice();

  /// The allocations for [amount]. Null when nothing was chosen (automatic).
  List<AllocationInput>? resolve(int amount) {
    if (split != null) return split;
    if (sourceId == null) return null;
    return [AllocationInput(sourceId!, amount)];
  }

  bool splitMatches(int amount) =>
      split == null || split!.fold<int>(0, (s, a) => s + a.amount) == amount;
}

/// Chip showing whose money is used; tap to pick one source or split.
class AllocationChipField extends ConsumerWidget {
  const AllocationChipField({
    super.key,
    required this.label,
    required this.amount,
    required this.accountId,
    required this.value,
    required this.onChanged,
    this.autoLabel = 'Automatic',
  });

  final String label;
  final int amount;
  final String? accountId;
  final AllocationChoice value;
  final ValueChanged<AllocationChoice> onChanged;
  final String autoLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final scheme = Theme.of(context).colorScheme;
    String name(String id) =>
        sources.where((s) => s.id == id).firstOrNull?.name ?? 'Unknown';
    String summary;
    if (value.split != null && value.split!.length > 1) {
      summary =
          'Split: ${value.split!.map((a) => '${name(a.sourceId)} ${Money.format(a.amount)}').join(' + ')}';
    } else if (value.sourceId != null) {
      summary = name(value.sourceId!);
    } else {
      summary = autoLabel;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
              color: scheme.surfaceContainerLowest,
            ),
            child: Row(
              children: [
                const Icon(Icons.sell_outlined, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final inAccount = accountId == null
        ? <String, int>{}
        : LedgerService.sourcesInAccount(
            ref.read(sourceBalancesProvider).value ?? const {},
            accountId!,
          );
    final how = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(autoLabel),
              onTap: () => Navigator.pop(ctx, 'auto'),
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Choose one source'),
              onTap: () => Navigator.pop(ctx, 'one'),
            ),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('Split across sources'),
              onTap: () => Navigator.pop(ctx, 'split'),
            ),
          ],
        ),
      ),
    );
    if (how == null || !context.mounted) return;
    if (how == 'auto') {
      onChanged(AllocationChoice.none);
    } else if (how == 'one') {
      final r = await pickSource(
        context,
        ref,
        selectedId: value.sourceId,
        balances: inAccount,
        title: 'Whose money?',
      );
      if (r?.value != null) onChanged(AllocationChoice(sourceId: r!.value));
    } else if (amount > 0) {
      final result = await showSplitSheet(
        context,
        amount: amount,
        initial: [
          AllocationInput(value.sourceId ?? otherMoneySourceId, amount),
        ],
        balancesInAccount: inAccount,
        title: 'Amount',
      );
      if (result != null) {
        onChanged(
          result.length == 1
              ? AllocationChoice(sourceId: result.first.sourceId)
              : AllocationChoice(split: result),
        );
      }
    }
  }
}
