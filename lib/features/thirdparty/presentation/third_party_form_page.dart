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
import '../../people/presentation/person_picker.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/pass_repository.dart';

/// Add or edit money borrowed from one person for another.
class ThirdPartyFormPage extends ConsumerStatefulWidget {
  const ThirdPartyFormPage({super.key, this.passId});

  final String? passId;

  @override
  ConsumerState<ThirdPartyFormPage> createState() => _ThirdPartyFormPageState();
}

class _ThirdPartyFormPageState extends ConsumerState<ThirdPartyFormPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _fromId;
  String? _forId;
  String? _accountId;
  bool _throughMe = true;
  bool _handedOver = true;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  DateTime? _collectBy;
  DateTime? _returnBy;

  /// Later steps are recorded: amount, date and path are fixed.
  bool _locked = false;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.passId != null;

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
    final repo = ref.read(passRepositoryProvider);
    final v = await repo.view(widget.passId!);
    if (v == null || !mounted) return;
    String? accountId;
    for (final e in v.entries) {
      if (e.kind == PassEntryKind.takenIn && e.transactionId != null) {
        accountId = (await ref
                .read(transactionRepositoryProvider)
                .get(e.transactionId!))
            ?.accountId;
      }
    }
    if (!mounted) return;
    setState(() {
      final p = v.pass;
      _amount.text = Money.format(p.amount)
          .replaceFirst('Rs ', '')
          .replaceAll(',', '');
      _note.text = p.note ?? '';
      _fromId = p.fromPersonId;
      _forId = p.forPersonId;
      _accountId = accountId;
      _throughMe = v.startedThroughMe;
      _handedOver = v.toHandOver == 0;
      _date = p.startDate;
      _collectBy = p.collectBy;
      _returnBy = p.returnBy;
      _locked = !v.isRewritable;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPerson(bool lender) async {
    final r = await pickPerson(
      context,
      ref,
      selectedId: lender ? _fromId : _forId,
    );
    if (r == null || !mounted) return;
    setState(() => lender ? _fromId = r.value : _forId = r.value);
  }

  Future<DateTime?> _pickDay(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateUtils.dateOnly(DateTime.now()),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  Future<void> _save() async {
    final amount = parseAmount(_amount.text) ?? 0;
    final from = _fromId;
    final forId = _forId;
    if (amount <= 0) {
      showMessage(context, 'Enter an amount above 0.');
      return;
    }
    if (from == null || forId == null) {
      showMessage(context, 'Choose both people.');
      return;
    }
    final draft = PassDraft(
      id: widget.passId,
      fromPersonId: from,
      forPersonId: forId,
      amount: amount,
      date: _date,
      throughMe: _throughMe,
      // Not needed once the first entries are fixed.
      accountId: _locked ? (_accountId ?? '-') : _accountId,
      handedOver: _handedOver,
      collectBy: _collectBy,
      returnBy: _returnBy,
      note: _note.text,
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(passRepositoryProvider);
      if (_isEdit) {
        await repo.update(draft);
      } else {
        await repo.create(draft);
      }
      if (mounted) context.pop();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _optionalDate(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      PickerField(
        label: label,
        leading: const Icon(Icons.event_outlined),
        value: value == null ? null : DateFormat('d MMM y').format(value),
        placeholder: 'No date (no reminder)',
        trailing: value == null
            ? Icons.keyboard_arrow_down
            : Icons.edit_calendar,
        onTap: () async {
          final d = await _pickDay(value);
          if (d != null) setState(() => onChanged(d));
        },
      ),
      if (value != null)
        TextButton(
          onPressed: () => setState(() => onChanged(null)),
          child: const Text('Clear date'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).value ?? const <PeopleData>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    ref.watch(sourceBalancesProvider);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final from = people.where((p) => p.id == _fromId).firstOrNull;
    final forWho = people.where((p) => p.id == _forId).firstOrNull;
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit 3rd party record' : '3rd party money'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            'Borrowed from one person for another. It is not your income, expense or debt.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_locked) ...[
            InlineEmpty(
              Icons.lock_outline,
              'Steps have been recorded, so the amount ${Money.format(parseAmount(_amount.text) ?? 0)}, date and path are fixed.',
            ),
          ] else
            AmountField(controller: _amount, autofocus: !_isEdit),
          const SizedBox(height: 16),
          PickerField(
            label: 'Borrowed from',
            iconKey: 'people',
            value: from?.name,
            onTap: () => _pickPerson(true),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'For whom',
            iconKey: 'people',
            value: forWho?.name,
            onTap: () => _pickPerson(false),
          ),
          if (!_locked) ...[
            const SizedBox(height: 16),
            const Text(
              'How did the money travel?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Through my account'),
                  selected: _throughMe,
                  onSelected: (_) => setState(() => _throughMe = true),
                ),
                ChoiceChip(
                  label: const Text('Directly between them'),
                  selected: !_throughMe,
                  onSelected: (_) => setState(() => _throughMe = false),
                ),
              ],
            ),
            if (_throughMe) ...[
              const SizedBox(height: 16),
              PickerField(
                label: 'My account',
                iconKey: account?.iconKey,
                iconColor: account == null ? null : Color(account.colorValue),
                value: account?.name,
                onTap: () async {
                  final r = await pickAccount(
                    context,
                    ref,
                    selectedId: _accountId,
                  );
                  if (r != null) setState(() => _accountId = r.value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Already given to them'),
                value: _handedOver,
                onChanged: (v) => setState(() => _handedOver = v),
              ),
            ],
            const SizedBox(height: 16),
            PickerField(
              label: 'Date',
              leading: const Icon(Icons.today_outlined),
              value: DateFormat('d MMM y').format(_date),
              onTap: () async {
                final d = await _pickDay(_date);
                if (d != null) setState(() => _date = d);
              },
            ),
          ],
          const SizedBox(height: 16),
          _optionalDate(
            'Collect it back by',
            _collectBy,
            (d) => _collectBy = d,
          ),
          const SizedBox(height: 16),
          _optionalDate(
            'Return it to the lender by',
            _returnBy,
            (d) => _returnBy = d,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit ? 'Save changes' : 'Save record',
      ),
    );
  }
}
