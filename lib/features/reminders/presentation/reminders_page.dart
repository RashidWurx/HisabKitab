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
    final upcoming = all
        .where((r) => r.repeat != ReminderRepeat.none || !r.remindAt.isBefore(now))
        .toList();
    final past = all
        .where((r) => r.repeat == ReminderRepeat.none && r.remindAt.isBefore(now))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Custom reminders')),
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
                if (upcoming.isNotEmpty) ...[
                  const SectionTitle('Upcoming'),
                  for (final r in upcoming) _tile(context, ref, r, false),
                ],
                if (past.isNotEmpty) ...[
                  const SectionTitle('Done'),
                  for (final r in past) _tile(context, ref, r, true),
                ],
              ],
            ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, CustomReminder r, bool done) {
    final scheme = Theme.of(context).colorScheme;
    final canPay = r.amount != null || r.categoryId != null || r.accountId != null;
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
                  onPressed: () => openExpenseFor(context, r),
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

/// Opens "Add expense" pre-filled from a reminder.
void openExpenseFor(BuildContext context, CustomReminder r) {
  final q = <String, String>{
    if (r.amount != null) 'amount': '${r.amount}',
    if (r.categoryId != null) 'category': r.categoryId!,
    if (r.accountId != null) 'account': r.accountId!,
  };
  context.push(Uri(path: '/transaction/new/expense', queryParameters: q.isEmpty ? null : q).toString());
}

class ReminderFormPage extends ConsumerStatefulWidget {
  const ReminderFormPage({super.key, this.reminderId});

  final String? reminderId;

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
        title: Text(_isEdit ? 'Edit reminder' : 'New reminder'),
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
        children: [
          TextField(
            controller: _title,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Pay rent, Send money home',
            ),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Date and time',
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
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountFormatters,
            decoration: const InputDecoration(
              labelText: 'Amount (optional)',
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Category (optional)',
            iconKey: category?.iconKey,
            iconColor: category == null ? null : Color(category.colorValue),
            value: category?.name,
            placeholder: 'None',
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? 'Save changes' : 'Add reminder'),
          ),
        ],
      ),
    );
  }
}
