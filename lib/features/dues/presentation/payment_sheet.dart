import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/due_models.dart';
import 'due_widgets.dart';

/// "Mark received" / "Mark paid": records a (possibly partial) payment.
/// Returns true if a payment was saved.
Future<bool> showPaymentSheet(
  BuildContext context,
  WidgetRef ref,
  DueView view,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PaymentSheet(view: view),
  );
  return saved ?? false;
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.view});

  final DueView view;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Money.format(widget.view.remaining)
        .replaceFirst('Rs ', '')
        .replaceAll(',', ''),
  );
  late String _accountId = widget.view.due.accountId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  bool get _receiving => widget.view.isReceivable;

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
    var allowOverpay = false;
    if (amount > widget.view.remaining) {
      final ok = await confirmDialog(
        context,
        title: 'More than remaining',
        message:
            '${Money.format(amount)} is more than the ${Money.format(widget.view.remaining)} still due. Record it anyway?',
        confirmLabel: 'Record anyway',
      );
      if (!ok || !mounted) return;
      allowOverpay = true;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(dueRepositoryProvider)
          .recordPayment(
            widget.view.due.id,
            amount: amount,
            accountId: _accountId,
            date: _date,
            allowOverpay: allowOverpay,
          );
      if (mounted) Navigator.pop(context, true);
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final amount = parseAmount(_amount.text) ?? 0;
    final after = widget.view.remaining - amount;
    final title = _receiving ? 'Mark received' : 'Mark paid';
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
                    title,
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
              'Payment amount',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountFormatters,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: 'Rs '),
            ),
            const SizedBox(height: 14),
            PickerField(
              label: _receiving ? 'Into account' : 'From account',
              iconKey: account?.iconKey,
              iconColor: account == null ? null : Color(account.colorValue),
              value: account?.name,
              onTap: () async {
                final r = await pickAccount(
                  context,
                  ref,
                  selectedId: _accountId,
                );
                if (r?.value != null) setState(() => _accountId = r!.value!);
              },
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('After this payment'),
                  Text(
                    after <= 0
                        ? (after < 0 ? 'Overpaid ${Money.format(-after)}' : 'Settled')
                        : '${Money.format(after)} remaining',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: statusColor(
                        context,
                        after == 0
                            ? DueStatus.settled
                            : after < 0
                            ? DueStatus.pending
                            : DueStatus.overdue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}
