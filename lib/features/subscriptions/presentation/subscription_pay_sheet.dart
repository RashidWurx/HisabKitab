import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../dues/presentation/due_widgets.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/subscription_logic.dart';

/// "Mark paid": records the renewal as an expense. The amount can change.
Future<bool> showSubscriptionPaySheet(
  BuildContext context,
  WidgetRef ref,
  Subscription sub,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PaySheet(sub: sub),
  );
  return saved ?? false;
}

class _PaySheet extends ConsumerStatefulWidget {
  const _PaySheet({required this.sub});

  final Subscription sub;

  @override
  ConsumerState<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<_PaySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Money.format(widget.sub.amount)
        .replaceFirst('Rs ', '')
        .replaceAll(',', ''),
  );
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text) ?? 0;
    if (amount <= 0) {
      showMessage(context, 'Enter an amount above 0.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(subscriptionRepositoryProvider)
          .markPaid(widget.sub.id, amount: amount, date: _date);
      if (mounted) Navigator.pop(context, true);
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => a.id == widget.sub.accountId)
        .firstOrNull;
    final next = nextBillingDate(
      from: widget.sub.nextDueDate,
      unit: widget.sub.billingUnit,
      every: widget.sub.billingEvery,
      anchorDay: widget.sub.anchorDay,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pay ${widget.sub.name}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Amount',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountFormatters,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: 'Rs '),
            ),
            const SizedBox(height: 14),
            PickerField(
              label: 'Date',
              leading: const Icon(Icons.calendar_today_outlined),
              value: formatDate(_date),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 14),
            InfoRow('Paid from', account?.name ?? '-'),
            InfoRow('Next renewal', formatDate(next)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Mark paid'),
            ),
          ],
        ),
      ),
    );
  }
}
