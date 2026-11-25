import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_models.dart';
import '../data/account_repository.dart';

const accountTypeLabels = {
  AccountType.bank: 'Bank',
  AccountType.mobileWallet: 'Mobile wallet',
  AccountType.cash: 'Cash',
  AccountType.onlineWallet: 'Online wallet',
  AccountType.savings: 'Savings',
  AccountType.other: 'Other',
};

const _typeDefaultIcon = {
  AccountType.bank: 'bank',
  AccountType.mobileWallet: 'phone',
  AccountType.cash: 'cash',
  AccountType.onlineWallet: 'card',
  AccountType.savings: 'savings',
  AccountType.other: 'wallet',
};

class _SplitRow {
  _SplitRow(this.sourceId, String amount)
    : controller = TextEditingController(text: amount);
  String? sourceId;
  final TextEditingController controller;
}

class AccountFormPage extends ConsumerStatefulWidget {
  const AccountFormPage({super.key, this.accountId, this.initialType});

  final String? accountId;
  final AccountType? initialType;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  final _name = TextEditingController();
  final _opening = TextEditingController();
  final _note = TextEditingController();
  final _goal = TextEditingController();
  final _split = <_SplitRow>[];

  AccountType _type = AccountType.bank;
  String _iconKey = 'bank';
  int _color = 0xFF112E4E;
  String? _defaultSourceId;
  bool _includeInTotal = true;
  bool _active = true;
  DateTime? _goalDate;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      if (widget.initialType != null) {
        _type = widget.initialType!;
        _iconKey = _typeDefaultIcon[_type]!;
      }
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final repo = ref.read(accountRepositoryProvider);
    final a = await repo.get(widget.accountId!);
    if (a == null || !mounted) return;
    final split = await repo.openingSplit(a.id);
    setState(() {
      _name.text = a.name;
      _opening.text = a.openingBalance == 0 ? '' : _plain(a.openingBalance);
      _note.text = a.note ?? '';
      _type = a.type;
      _iconKey = a.iconKey;
      _color = a.colorValue;
      _defaultSourceId = a.defaultSpendingSourceId;
      _includeInTotal = a.includeInTotal;
      _active = a.status == ActiveStatus.active;
      _goal.text = a.goalAmount == null ? '' : _plain(a.goalAmount!);
      _goalDate = a.goalDate;
      for (final s in split) {
        _split.add(_SplitRow(s.sourceId, _plain(s.amount)));
      }
      _loaded = true;
    });
  }

  /// 150000 paisa -> "1500", 150050 -> "1500.50" (for editing).
  String _plain(int paisa) {
    final f = Money.format(paisa).replaceFirst('Rs ', '').replaceAll(',', '');
    return f;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _note.dispose();
    _goal.dispose();
    for (final r in _split) {
      r.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final opening = _opening.text.trim().isEmpty
        ? 0
        : parseAmount(_opening.text);
    if (opening == null) {
      showMessage(context, 'Enter a valid opening balance.');
      return;
    }
    final splits = <AllocationInput>[];
    for (final r in _split) {
      final amount = parseAmount(r.controller.text);
      if (r.sourceId == null || amount == null || amount == 0) continue;
      splits.add(AllocationInput(r.sourceId!, amount));
    }
    final goal = _goal.text.trim().isEmpty ? null : parseAmount(_goal.text);
    setState(() => _saving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .save(
            AccountDraft(
              id: widget.accountId,
              name: _name.text,
              type: _type,
              openingBalance: opening,
              openingSplit: splits,
              defaultSpendingSourceId: _defaultSourceId,
              status: _active ? ActiveStatus.active : ActiveStatus.inactive,
              includeInTotal: _includeInTotal,
              colorValue: _color,
              iconKey: _iconKey,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
              goalAmount: _type == AccountType.savings ? goal : null,
              goalDate: _type == AccountType.savings ? _goalDate : null,
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
    final sources = ref.watch(sourcesProvider).value ?? const [];
    String? sourceName(String? id) {
      for (final s in sources) {
        if (s.id == id) return s.name;
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit account' : 'New account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Meezan Bank, JazzCash, Cash in hand',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AccountType.values)
                ChoiceChip(
                  label: Text(accountTypeLabels[t]!),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    if (!_isEdit) _iconKey = _typeDefaultIcon[t]!;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          IconColorField(
            iconKey: _iconKey,
            colorValue: _color,
            onChanged: (i, c) => setState(() {
              _iconKey = i;
              _color = c;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: amountFormatters,
            decoration: const InputDecoration(
              labelText: 'Current balance',
              prefixText: 'Rs ',
              helperText: 'What is in this account right now',
            ),
          ),
          const SizedBox(height: 8),
          _splitEditor(sources),
          const SizedBox(height: 16),
          PickerField(
            label: 'Default spending source (optional)',
            value: sourceName(_defaultSourceId),
            placeholder: 'None',
            onTap: () async {
              final r = await pickSource(
                context,
                ref,
                selectedId: _defaultSourceId,
                allowNone: true,
              );
              if (r != null) setState(() => _defaultSourceId = r.value);
            },
          ),
          if (_type == AccountType.savings) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _goal,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ), inputFormatters: amountFormatters,
              decoration: const InputDecoration(
                labelText: 'Savings goal (optional)',
                prefixText: 'Rs ',
              ),
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Goal date (optional)',
              value: _goalDate == null
                  ? null
                  : '${_goalDate!.day}/${_goalDate!.month}/${_goalDate!.year}',
              placeholder: 'No date',
              trailing: Icons.calendar_today_outlined,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _goalDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _goalDate = d);
              },
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include in total balance'),
            value: _includeInTotal,
            onChanged: (v) => setState(() => _includeInTotal = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text('Inactive accounts are hidden from pickers'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit ? 'Save changes' : 'Add account',
      ),
    );
  }

  Widget _splitEditor(List<dynamic> sources) {
    final named = sources.where(
      (s) => s.id != otherMoneySourceId && !s.isArchived,
    );
    if (named.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Whose money is it? Split the balance across your sources. Anything not split counts as "Other money".',
          style: TextStyle(fontSize: 13),
        ),
        for (final row in _split)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PickerField(
                    label: '',
                    value: row.sourceId == null
                        ? null
                        : sources
                              .firstWhere((s) => s.id == row.sourceId)
                              .name as String,
                    placeholder: 'Source',
                    onTap: () async {
                      final r = await pickSource(
                        context,
                        ref,
                        selectedId: row.sourceId,
                        exclude: {otherMoneySourceId},
                      );
                      if (r?.value != null) {
                        setState(() => row.sourceId = r!.value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ), inputFormatters: amountFormatters,
                    decoration: const InputDecoration(
                      prefixText: 'Rs ',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _split.remove(row)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _split.add(_SplitRow(null, ''))),
          icon: const Icon(Icons.add),
          label: const Text('Split by source'),
        ),
      ],
    );
  }
}
