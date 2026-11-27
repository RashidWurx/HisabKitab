import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/reminder_repository.dart';
import 'planned_pay_sheet.dart';

String repeatLabel(ReminderRepeat r, int? every) => switch (r) {
  ReminderRepeat.none => 'Does not repeat',
  ReminderRepeat.daily => 'Every day',
  ReminderRepeat.weekly => 'Every week',
  ReminderRepeat.monthly => 'Every month',
  ReminderRepeat.everyNDays => 'Every ${every ?? 1} days',
};

class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(remindersProvider).value ?? const <CustomReminder>[];
    final now = DateTime.now();
    final unpaid = all.where((r) => r.isUnpaid(now)).toList();
    // A payment that is switched off (paid, even early) is finished.
    bool isDone(CustomReminder r) =>
        (r.isPayment && !r.isActive) ||
        (r.repeat == ReminderRepeat.none && r.remindAt.isBefore(now));
    final upcoming = all.where((r) => !r.isUnpaid(now) && !isDone(r)).toList();
    final past = all.where((r) => !r.isUnpaid(now) && isDone(r)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders & payments')),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        heroTag: 'add-reminder',
        onPressed: () => context.push('/reminders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none,
              title: 'No reminders yet',
              message:
                  'Add reminders for anything: pay rent, send money home, renew a card.',
              actionLabel: 'Add reminder',
              onAction: () => context.push('/reminders/new'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: [
                if (unpaid.isNotEmpty) ...[
                  const SectionTitle('Unpaid'),
                  for (final r in unpaid) ReminderTile(r),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SectionTitle('Upcoming'),
                  for (final r in upcoming) ReminderTile(r),
                ],
                if (past.isNotEmpty) ...[
                  const SectionTitle('Paid or finished'),
                  for (final r in past) ReminderTile(r, done: true),
                ],
              ],
            ),
    );
  }

}

/// One reminder (with its switch) or planned payment (with "Mark paid").
class ReminderTile extends ConsumerWidget {
  const ReminderTile(this.reminder, {super.key, this.done = false});

  final CustomReminder reminder;
  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reminder;
    final scheme = Theme.of(context).colorScheme;
    if (r.isPayment) return _PaymentCard(r);
    final canPay = r.categoryId != null || r.accountId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: done || !r.isActive ? 0.6 : 1,
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          onTap: () => context.push('/reminders/${r.id}/edit'),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  r.repeat == ReminderRepeat.none
                      ? Icons.notifications_none
                      : Icons.repeat,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${DateFormat('d MMM, h:mm a').format(r.remindAt)} · ${repeatLabel(r.repeat, r.repeatEveryDays)}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    if (r.amount != null)
                      MoneyText(
                        -r.amount!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              if (canPay)
                TextButton(
                  onPressed: () => context.push(expenseRouteFor(r)),
                  child: const Text('Pay'),
                ),
              Switch(
                value: r.isActive,
                onChanged: (v) =>
                    ref.read(reminderRepositoryProvider).setActive(r.id, v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A planned payment. No switch: the only action is "Mark paid", so it cannot
/// be hidden by mistake.
class _PaymentCard extends ConsumerWidget {
  const _PaymentCard(this.payment);

  final CustomReminder payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = payment;
    final scheme = Theme.of(context).colorScheme;
    final unpaid = r.isUnpaid(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push('/reminders/${r.id}/edit'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MoneyText(
                  -r.amount!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              !r.isActive
                  ? 'Paid or switched off'
                  : '${unpaid ? 'Unpaid, was due' : 'Pay on'} ${DateFormat('d MMM y, h:mm a').format(r.remindAt)}'
                        '${r.repeat == ReminderRepeat.none ? '' : ' · ${repeatLabel(r.repeat, r.repeatEveryDays)}'}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (r.isActive)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => showPlannedPaySheet(context, ref, r),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark paid'),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Plan it again?',
                      message:
                          'Do this only if "${r.title}" was not paid. Check Activity first.',
                      confirmLabel: 'Not paid yet',
                    );
                    if (ok) {
                      await ref
                          .read(reminderRepositoryProvider)
                          .setActive(r.id, true);
                    }
                  },
                  child: const Text('Not paid? Restore'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReminderFormPage extends ConsumerStatefulWidget {
  const ReminderFormPage({super.key, this.reminderId, this.payment = false});

  final String? reminderId;

  /// Opened as "Plan a payment": the amount is required.
  final bool payment;

  @override
  ConsumerState<ReminderFormPage> createState() => _ReminderFormPageState();
}

class _ReminderFormPageState extends ConsumerState<ReminderFormPage> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _every = TextEditingController(text: '2');

  DateTime _at = DateTime.now().add(const Duration(days: 1)).copyWith(
    hour: 9,
    minute: 0,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
  ReminderRepeat _repeat = ReminderRepeat.none;
  String? _categoryId;
  String? _accountId;
  bool _active = true;
  bool _loaded = false;
  bool _saving = false;
  late bool _payment = widget.payment;

  bool get _isEdit => widget.reminderId != null;

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
    final r = await ref.read(reminderRepositoryProvider).get(widget.reminderId!);
    if (r == null || !mounted) return;
    setState(() {
      _title.text = r.title;
      _amount.text = r.amount == null
          ? ''
          : Money.format(r.amount!).replaceFirst('Rs ', '').replaceAll(',', '');
      _at = r.remindAt;
      _repeat = r.repeat;
      _every.text = '${r.repeatEveryDays ?? 2}';
      _categoryId = r.categoryId;
      _accountId = r.accountId;
      _active = r.isActive;
      _payment = r.isPayment;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _every.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) return;
    setState(
      () => _at = DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _save() async {
    final amount = _amount.text.trim().isEmpty ? null : parseAmount(_amount.text);
    if (_payment && (amount == null || amount <= 0)) {
      showMessage(context, 'Enter the amount to pay.');
      return;
    }
    if (_payment && _categoryId == null) {
      showMessage(context, 'Choose a category.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(reminderRepositoryProvider)
          .save(
            ReminderDraft(
              id: widget.reminderId,
              title: _title.text,
              amount: amount,
              categoryId: _categoryId,
              accountId: _accountId,
              remindAt: _at,
              repeat: _repeat,
              repeatEveryDays: int.tryParse(_every.text),
              isActive: _active,
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
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final category = cats.where((c) => c.id == _categoryId).firstOrNull;
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _payment
              ? (_isEdit ? 'Edit planned payment' : 'Plan a payment')
              : (_isEdit ? 'Edit reminder' : 'New reminder'),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Delete reminder?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (ok) {
                  await ref.read(reminderRepositoryProvider).delete(widget.reminderId!);
                  if (context.mounted) context.pop();
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_payment) ...[
            Text(
              'Nothing leaves your account until you mark it as paid. '
              'You will be asked on the date.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _title,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _payment ? 'What is it for?' : 'Title',
              hintText: _payment
                  ? 'Siblings, Rent, School fee'
                  : 'Pay rent, Send money home',
            ),
          ),
          if (_payment) ...[const SizedBox(height: 16), _amountField()],
          const SizedBox(height: 16),
          PickerField(
            label: _payment ? 'Pay on' : 'Date and time',
            leading: const Icon(Icons.notifications_none),
            value: DateFormat('d MMM y, h:mm a').format(_at),
            onTap: _pickDateTime,
          ),
          const SizedBox(height: 16),
          const Text(
            'Repeat',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in ReminderRepeat.values)
                ChoiceChip(
                  label: Text(switch (r) {
                    ReminderRepeat.none => 'None',
                    ReminderRepeat.daily => 'Daily',
                    ReminderRepeat.weekly => 'Weekly',
                    ReminderRepeat.monthly => 'Monthly',
                    ReminderRepeat.everyNDays => 'Every N days',
                  }),
                  selected: _repeat == r,
                  onSelected: (_) => setState(() => _repeat = r),
                ),
            ],
          ),
          if (_repeat == ReminderRepeat.everyNDays) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _every,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Every how many days'),
            ),
          ],
          if (!_payment) ...[const SizedBox(height: 16), _amountField()],
          const SizedBox(height: 16),
          PickerField(
            label: _payment ? 'Category' : 'Category (optional)',
            iconKey: category?.iconKey,
            iconColor: category == null ? null : Color(category.colorValue),
            value: category?.name,
            placeholder: _payment ? 'Choose' : 'None',
            onTap: () async {
              final r = await pickCategory(
                context,
                ref,
                kind: CategoryKind.expense,
                selectedId: _categoryId,
                allowNone: !_payment,
              );
              if (r != null) setState(() => _categoryId = r.value);
            },
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Account (optional)',
            iconKey: account?.iconKey,
            iconColor: account == null ? null : Color(account.colorValue),
            value: account?.name,
            placeholder: 'None',
            onTap: () async {
              final r = await pickAccount(
                context,
                ref,
                selectedId: _accountId,
                allowNone: true,
              );
              if (r != null) setState(() => _accountId = r.value);
            },
          ),
          if (!_payment) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit
            ? 'Save changes'
            : (_payment ? 'Plan payment' : 'Add reminder'),
      ),
    );
  }

  Widget _amountField() => TextField(
    controller: _amount,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: amountFormatters,
    decoration: InputDecoration(
      labelText: _payment ? 'Amount' : 'Amount (optional, makes it a payment)',
      prefixText: 'Rs ',
    ),
  );
}
