import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';

/// "Mark paid" for a planned payment: one button takes the money from the
/// account and adds the expense to Activity.
Future<void> showPlannedPaySheet(
  BuildContext context,
  WidgetRef ref,
  CustomReminder payment,
) async {
  final done = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PlannedPaySheet(payment),
  );
  if (done != null && context.mounted) showMessage(context, done);
}

class _PlannedPaySheet extends ConsumerStatefulWidget {
  const _PlannedPaySheet(this.payment);

  final CustomReminder payment;

  @override
  ConsumerState<_PlannedPaySheet> createState() => _PlannedPaySheetState();
}

class _PlannedPaySheetState extends ConsumerState<_PlannedPaySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Money.format(widget.payment.amount ?? 0)
        .replaceFirst('Rs ', '')
        .replaceAll(',', ''),
  );
  late String? _accountId = widget.payment.accountId;
  late String? _categoryId = widget.payment.categoryId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay(String? accountId, String accountName) async {
    final amount = parseAmount(_amount.text) ?? 0;
    final categoryId = _categoryId;
    final problem = amount <= 0
        ? 'Enter an amount above 0.'
        : accountId == null
        ? 'Choose an account.'
        : categoryId == null
        ? 'Choose a category.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(reminderRepositoryProvider)
          .payNow(
            widget.payment.id,
            occurrence: widget.payment.remindAt,
            amount: amount,
            accountId: accountId!,
            categoryId: categoryId!,
            date: _date,
          );
      if (mounted) {
        Navigator.pop(
          context,
          '${Money.format(amount)} paid from $accountName. It is in Activity.',
        );
      }
    } on LedgerException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final balances = LedgerService.accountTotals(
      ref.watch(sourceBalancesProvider).value ?? const {},
    );
    final accountId =
        _accountId ??
        accounts
            .where((a) => !a.isArchived && a.status == ActiveStatus.active)
            .firstOrNull
            ?.id;
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;
    final amount = parseAmount(_amount.text) ?? 0;
    final balance = balances[accountId] ?? 0;
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paid: ${widget.payment.title}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            AmountField(
              controller: _amount,
              autofocus: false,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            PickerField(
              label: 'Paid from',
              iconKey: account?.iconKey,
              iconColor: account == null ? null : Color(account.colorValue),
              value: account?.name,
              onTap: () async {
                final r = await pickAccount(
                  context,
                  ref,
                  selectedId: accountId,
                );
                if (r != null) setState(() => _accountId = r.value);
              },
            ),
            if (account != null) ...[
              const SizedBox(height: 6),
              Text(
                'Balance after: ${Money.format(balance - amount)}',
                style: TextStyle(
                  color: balance - amount < 0 ? colors.negative : null,
                ),
              ),
            ],
            const SizedBox(height: 16),
            PickerField(
              label: 'Category',
              iconKey: category?.iconKey,
              iconColor: category == null ? null : Color(category.colorValue),
              value: category?.name,
              onTap: () async {
                final r = await pickCategory(
                  context,
                  ref,
                  kind: CategoryKind.expense,
                  selectedId: _categoryId,
                );
                if (r != null) setState(() => _categoryId = r.value);
              },
            ),
            const SizedBox(height: 16),
            PickerField(
              label: 'Date',
              leading: const Icon(Icons.today_outlined),
              value: DateFormat('d MMM y').format(_date),
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.negative)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () => _pay(accountId, account?.name ?? ''),
                child: Text('Confirm payment of ${Money.format(amount)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
