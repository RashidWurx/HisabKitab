import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../dues/presentation/due_widgets.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/subscription_repository.dart';
import 'subscriptions_page.dart' show subscriptionIdeas;

const _unitLabels = {
  BillingUnit.day: 'Days',
  BillingUnit.week: 'Weeks',
  BillingUnit.month: 'Months',
  BillingUnit.year: 'Years',
};

class SubscriptionFormPage extends ConsumerStatefulWidget {
  const SubscriptionFormPage({super.key, this.subscriptionId, this.initialName});

  final String? subscriptionId;
  final String? initialName;

  @override
  ConsumerState<SubscriptionFormPage> createState() =>
      _SubscriptionFormPageState();
}

class _SubscriptionFormPageState extends ConsumerState<SubscriptionFormPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? '',
  );
  final _amount = TextEditingController();
  final _every = TextEditingController(text: '1');
  final _remindDays = TextEditingController();
  final _note = TextEditingController();

  BillingUnit _unit = BillingUnit.month;
  DateTime _nextDue = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 30)));
  String? _accountId;
  String? _categoryId;
  SubscriptionStatus _status = SubscriptionStatus.active;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.subscriptionId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final s = await ref
        .read(subscriptionRepositoryProvider)
        .get(widget.subscriptionId!);
    if (s == null || !mounted) return;
    setState(() {
      _name.text = s.name;
      _amount.text = Money.format(s.amount)
          .replaceFirst('Rs ', '')
          .replaceAll(',', '');
      _every.text = '${s.billingEvery}';
      _unit = s.billingUnit;
      _nextDue = s.nextDueDate;
      _accountId = s.accountId;
      _categoryId = s.categoryId;
      _remindDays.text = s.reminderDaysBefore?.toString() ?? '';
      _status = s.status;
      _note.text = s.note ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _every.dispose();
    _remindDays.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text) ?? 0;
    final accountId = _accountId ??
        (ref.read(accountsProvider).value ?? const <Account>[])
            .where((a) => !a.isArchived && a.status == ActiveStatus.active)
            .firstOrNull
            ?.id;
    if (accountId == null) {
      showMessage(context, 'Add an account first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(subscriptionRepositoryProvider)
          .save(
            SubscriptionDraft(
              id: widget.subscriptionId,
              name: _name.text,
              amount: amount,
              billingUnit: _unit,
              billingEvery: int.tryParse(_every.text) ?? 1,
              nextDueDate: _nextDue,
              accountId: accountId,
              categoryId: _categoryId,
              reminderDaysBefore: int.tryParse(_remindDays.text.trim()),
              status: _status,
              note: _note.text,
            ),
          );
      if (mounted) context.pop();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final account = accounts
        .where((a) => a.id == (_accountId))
        .firstOrNull ??
        (_isEdit
            ? null
            : accounts
                  .where((a) => !a.isArchived && a.status == ActiveStatus.active)
                  .firstOrNull);
    final category = categories.where((c) => c.id == _categoryId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit subscription' : 'New subscription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Spotify, Google One, VPS',
            ),
          ),
          if (!_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final idea in subscriptionIdeas)
                    ActionChip(
                      label: Text(idea),
                      onPressed: () => setState(() => _name.text = idea),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountFormatters,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: 'Rs '),
          ),
          const SizedBox(height: 16),
          const Text(
            'Billing cycle',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Every', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 12),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _every,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<BillingUnit>(
                  initialValue: _unit,
                  items: [
                    for (final u in BillingUnit.values)
                      DropdownMenuItem(value: u, child: Text(_unitLabels[u]!)),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? _unit),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Next due date',
            leading: const Icon(Icons.calendar_today_outlined),
            value: formatDate(_nextDue),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _nextDue,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _nextDue = d);
            },
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Pay from account',
            iconKey: account?.iconKey,
            iconColor: account == null ? null : Color(account.colorValue),
            value: account?.name,
            placeholder: 'Choose account',
            onTap: () async {
              final r = await pickAccount(context, ref, selectedId: _accountId);
              if (r?.value != null) setState(() => _accountId = r!.value);
            },
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Category',
            iconKey: category?.iconKey,
            iconColor: category == null ? null : Color(category.colorValue),
            value: category?.name,
            placeholder: 'Subscriptions (default)',
            onTap: () async {
              final r = await pickCategory(
                context,
                ref,
                kind: CategoryKind.expense,
                selectedId: _categoryId,
                allowNone: true,
              );
              if (r != null) setState(() => _categoryId = r.value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _remindDays,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Remind me days before (optional)',
              helperText: 'Leave empty to use the default from Settings',
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 16),
            SegmentedButton<SubscriptionStatus>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SubscriptionStatus.active, label: Text('Active')),
                ButtonSegment(value: SubscriptionStatus.paused, label: Text('Paused')),
                ButtonSegment(value: SubscriptionStatus.cancelled, label: Text('Cancelled')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit ? 'Save changes' : 'Add subscription',
      ),
    );
  }
}
