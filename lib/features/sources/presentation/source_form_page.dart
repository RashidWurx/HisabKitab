import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/source_repository.dart';

const sourceTypeLabels = {
  SourceType.job: 'Job',
  SourceType.freelance: 'Freelance',
  SourceType.business: 'Business',
  SourceType.other: 'Other',
};

const scheduleLabels = {
  PayScheduleType.monthly: 'Monthly',
  PayScheduleType.weekly: 'Weekly',
  PayScheduleType.everyNDays: 'Every N days',
  PayScheduleType.irregular: 'Irregular',
};

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class SourceFormPage extends ConsumerStatefulWidget {
  const SourceFormPage({super.key, this.sourceId});

  final String? sourceId;

  @override
  ConsumerState<SourceFormPage> createState() => _SourceFormPageState();
}

class _SourceFormPageState extends ConsumerState<SourceFormPage> {
  final _name = TextEditingController();
  final _expected = TextEditingController();
  final _note = TextEditingController();
  final _interval = TextEditingController(text: '14');

  SourceType _type = SourceType.job;
  String _iconKey = 'work';
  int _color = 0xFF2A4E76;
  String? _accountId;
  PayScheduleType? _schedule;
  int _payDay = 1;
  DateTime? _anchor;
  bool _active = true;
  bool _builtIn = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.sourceId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  String _plain(int paisa) =>
      Money.format(paisa).replaceFirst('Rs ', '').replaceAll(',', '');

  Future<void> _load() async {
    final IncomeSource? s = await ref
        .read(sourceRepositoryProvider)
        .get(widget.sourceId!);
    if (s == null || !mounted) return;
    setState(() {
      _name.text = s.name;
      _expected.text = s.expectedAmount == null ? '' : _plain(s.expectedAmount!);
      _note.text = s.note ?? '';
      _type = s.type;
      _iconKey = s.iconKey;
      _color = s.colorValue;
      _accountId = s.linkedAccountId;
      _schedule = s.payScheduleType;
      _payDay = s.payDay ?? 1;
      _anchor = s.payAnchorDate;
      _interval.text = '${s.payIntervalDays ?? 14}';
      _active = s.status == ActiveStatus.active;
      _builtIn = s.isBuiltIn;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _expected.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final expected = _expected.text.trim().isEmpty
        ? null
        : parseAmount(_expected.text);
    if (_expected.text.trim().isNotEmpty && expected == null) {
      showMessage(context, 'Enter a valid expected amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(sourceRepositoryProvider)
          .save(
            SourceDraft(
              id: widget.sourceId,
              name: _name.text,
              type: _type,
              linkedAccountId: _accountId,
              expectedAmount: expected,
              payScheduleType: _schedule,
              payDay: (_schedule == PayScheduleType.monthly ||
                      _schedule == PayScheduleType.weekly)
                  ? _payDay
                  : null,
              payIntervalDays: _schedule == PayScheduleType.everyNDays
                  ? int.tryParse(_interval.text)
                  : null,
              payAnchorDate: _schedule == PayScheduleType.everyNDays
                  ? (_anchor ?? DateTime.now())
                  : null,
              status: _active ? ActiveStatus.active : ActiveStatus.inactive,
              colorValue: _color,
              iconKey: _iconKey,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
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
    final accounts = ref.watch(accountsProvider).value ?? const [];
    String? accountName() {
      for (final a in accounts) {
        if (a.id == _accountId) return a.name;
      }
      return null;
    }

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit source' : 'New source')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_builtIn)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '"Other money" is built in. It holds money with no real source (unsplit balances, borrowed money, gifts). You can only change its icon and colour.',
              ),
            ),
          TextField(
            controller: _name,
            enabled: !_builtIn,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Job 1, Freelancing, eBay',
            ),
          ),
          if (!_builtIn) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in SourceType.values)
                  ChoiceChip(
                    label: Text(sourceTypeLabels[t]!),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          IconColorField(
            iconKey: _iconKey,
            colorValue: _color,
            onChanged: (i, c) => setState(() {
              _iconKey = i;
              _color = c;
            }),
          ),
          if (!_builtIn) ...[
            const SizedBox(height: 16),
            PickerField(
              label: 'Pays into account',
              iconKey: accountName() == null ? null : 'bank',
              value: accountName(),
              placeholder: 'Choose account',
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
            const SizedBox(height: 16),
            TextField(
              controller: _expected,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ), inputFormatters: amountFormatters,
              decoration: const InputDecoration(
                labelText: 'Expected amount (optional)',
                prefixText: 'Rs ',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pay schedule',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _schedule == null,
                  onSelected: (_) => setState(() => _schedule = null),
                ),
                for (final s in PayScheduleType.values)
                  ChoiceChip(
                    label: Text(scheduleLabels[s]!),
                    selected: _schedule == s,
                    onSelected: (_) => setState(() => _schedule = s),
                  ),
              ],
            ),
            if (_schedule == PayScheduleType.monthly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<int>(
                  initialValue: _payDay.clamp(1, 31),
                  decoration: const InputDecoration(labelText: 'Payday (day of month)'),
                  items: [
                    for (var d = 1; d <= 31; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() => _payDay = v ?? 1),
                ),
              ),
            if (_schedule == PayScheduleType.weekly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<int>(
                  initialValue: _payDay.clamp(1, 7),
                  decoration: const InputDecoration(labelText: 'Payday (weekday)'),
                  items: [
                    for (var d = 1; d <= 7; d++)
                      DropdownMenuItem(value: d, child: Text(_weekdays[d - 1])),
                  ],
                  onChanged: (v) => setState(() => _payDay = v ?? 1),
                ),
              ),
            if (_schedule == PayScheduleType.everyNDays)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Every how many days'),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text(
                'Inactive sources get no payday reminders',
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? 'Save changes' : 'Add source'),
          ),
        ],
      ),
    );
  }
}

/// True when [id] is the built-in "Other money" source.
bool isBuiltInSource(String id) => id == otherMoneySourceId;
