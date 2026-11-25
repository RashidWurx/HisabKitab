import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../../people/presentation/person_picker.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/presentation/allocation_chip.dart';
import '../data/due_repository.dart';
import '../domain/due_models.dart';
import 'due_widgets.dart';

/// Create (or edit) a due: Lend, Borrow, or Expected cash in.
class DueFormPage extends ConsumerStatefulWidget {
  const DueFormPage({super.key, this.kind, this.dueId, this.personId});

  final DueKind? kind;
  final String? dueId;

  /// Pre-selected person (when opened from a person page).
  final String? personId;

  @override
  ConsumerState<DueFormPage> createState() => _DueFormPageState();
}

class _DueFormPageState extends ConsumerState<DueFormPage> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _repeat = TextEditingController();

  late DueKind _kind = widget.kind ?? DueKind.expectedIncome;
  String? _personId;
  String? _sourceId;
  String? _accountId;
  AllocationChoice _alloc = AllocationChoice.none;
  DateTime _dueDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 7)),
  );
  DateTime? _reminderAt;
  bool _customReminder = false;
  bool _accountTouched = false;
  bool _loaded = false;
  bool _saving = false;
  DueView? _original;

  bool get _isEdit => widget.dueId != null;
  bool get _expected => _kind == DueKind.expectedIncome;
  bool get _lent => _kind == DueKind.lent;

  @override
  void initState() {
    super.initState();
    _personId = widget.personId;
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final v = await ref.read(dueRepositoryProvider).getView(widget.dueId!);
    if (v == null || !mounted) {
      if (mounted) context.pop();
      return;
    }
    final d = v.due;
    setState(() {
      _original = v;
      _kind = d.kind;
      _amount.text = Money.format(d.totalAmount)
          .replaceFirst('Rs ', '')
          .replaceAll(',', '');
      _title.text = d.title;
      _note.text = d.note ?? '';
      _personId = d.personId;
      _sourceId = d.sourceId;
      _accountId = d.accountId;
      _dueDate = d.currentDueDate;
      _reminderAt = d.reminderAt;
      _customReminder = d.reminderAt != null;
      _repeat.text = d.reminderRepeatDays?.toString() ?? '';
      _accountTouched = true;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    _repeat.dispose();
    super.dispose();
  }

  int get _amountPaisa => parseAmount(_amount.text) ?? 0;

  /// Account auto-fill: source's linked account, then the person's default
  /// account, then the last used account, then the first active one.
  void _autoAccount() {
    if (_accountTouched || _isEdit) return;
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final usable = accounts
        .where((a) => !a.isArchived && a.status == ActiveStatus.active)
        .toList();
    bool ok(String? id) => id != null && usable.any((a) => a.id == id);
    final sources = ref.read(sourcesProvider).value ?? const <IncomeSource>[];
    final people = ref.read(peopleProvider).value ?? const <PeopleData>[];
    final fromSource = sources.where((s) => s.id == _sourceId).firstOrNull;
    final fromPerson = people.where((p) => p.id == _personId).firstOrNull;
    final pick = ok(fromSource?.linkedAccountId)
        ? fromSource!.linkedAccountId
        : ok(fromPerson?.defaultAccountId)
        ? fromPerson!.defaultAccountId
        : ok(_accountId)
        ? _accountId
        : usable.firstOrNull?.id;
    _accountId = pick;
  }

  String _defaultTitle() {
    final people = ref.read(peopleProvider).value ?? const <PeopleData>[];
    final sources = ref.read(sourcesProvider).value ?? const <IncomeSource>[];
    final who = people.where((p) => p.id == _personId).firstOrNull?.name;
    final src = sources.where((s) => s.id == _sourceId).firstOrNull?.name;
    return switch (_kind) {
      DueKind.lent => 'Lent to ${who ?? 'someone'}',
      DueKind.borrowed => 'Borrowed from ${who ?? 'someone'}',
      DueKind.expectedIncome =>
        who != null
            ? 'Expected from $who'
            : (src != null ? '$src payment' : 'Expected cash in'),
    };
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    setState(
      () => _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final amount = _amountPaisa;
    if (amount <= 0) {
      showMessage(context, 'Enter an amount above 0.');
      return;
    }
    if (!_expected && _personId == null) {
      showMessage(context, 'Choose a person.');
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      showMessage(context, 'Choose an account.');
      return;
    }
    if (_alloc.split != null && !_alloc.splitMatches(amount)) {
      showMessage(context, 'The source split no longer matches the amount. Fix the split first.');
      return;
    }
    final allocations = _alloc.resolve(amount);

    // Lending more than a source has in the account: warn, allow.
    if (_lent && !_isEdit) {
      final balances = ref.read(sourceBalancesProvider).value ?? const {};
      final inAccount = LedgerService.sourcesInAccount(balances, accountId);
      final accountTotal = LedgerService.accountTotals(balances)[accountId] ?? 0;
      final short = allocations != null
          ? allocations.any((a) => (inAccount[a.sourceId] ?? 0) < a.amount)
          : accountTotal < amount;
      if (short) {
        final ok = await confirmDialog(
          context,
          title: 'Not enough money',
          message: 'This account (or source) does not have that much. Lend it anyway?',
          confirmLabel: 'Lend anyway',
        );
        if (!ok || !mounted) return;
      }
    }

    final title = _title.text.trim().isEmpty ? _defaultTitle() : _title.text;
    final repeat = int.tryParse(_repeat.text.trim());
    final draft = DueDraft(
      id: widget.dueId,
      title: title,
      kind: _kind,
      personId: _personId,
      sourceId: _sourceId,
      totalAmount: amount,
      accountId: accountId,
      dueDate: _dueDate,
      reminderAt: _customReminder ? _reminderAt : null,
      reminderRepeatDays: (repeat != null && repeat > 0) ? repeat : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      allocations: allocations,
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(dueRepositoryProvider);
      if (_isEdit) {
        await repo.update(draft);
        if (mounted) context.pop();
      } else {
        final id = await repo.create(draft);
        if (mounted) {
          context.pop();
          context.push('/dues/$id');
        }
      }
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final people = ref.watch(peopleProvider).value ?? const <PeopleData>[];
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    ref.watch(sourceBalancesProvider);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _autoAccount();
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final person = people.where((p) => p.id == _personId).firstOrNull;
    final source = sources.where((s) => s.id == _sourceId).firstOrNull;
    final title = switch (_kind) {
      DueKind.lent => _isEdit ? 'Edit lent money' : 'Lend',
      DueKind.borrowed => _isEdit ? 'Edit borrowed money' : 'Borrow',
      DueKind.expectedIncome => _isEdit ? 'Edit expected cash in' : 'Expected cash in',
    };
    final hasPayments = (_original?.paid ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AmountField(
            controller: _amount,
            autofocus: !_isEdit,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          PickerField(
            label: _expected ? 'Person (optional)' : 'Person',
            iconKey: 'people',
            value: person?.name,
            placeholder: 'Choose person',
            onTap: () async {
              final r = await pickPerson(
                context,
                ref,
                selectedId: _personId,
                allowNone: _expected,
              );
              if (r != null) {
                setState(() {
                  _personId = r.value;
                  _accountTouched = false;
                });
              }
            },
          ),
          if (_expected) ...[
            const SizedBox(height: 14),
            PickerField(
              label: 'From source (optional)',
              iconKey: 'work',
              value: source?.name,
              placeholder: 'None',
              onTap: () async {
                final r = await pickSource(
                  context,
                  ref,
                  selectedId: _sourceId,
                  allowNone: true,
                );
                if (r != null) {
                  setState(() {
                    _sourceId = r.value;
                    _accountTouched = false;
                  });
                }
              },
            ),
          ],
          const SizedBox(height: 14),
          PickerField(
            label: _expected
                ? 'Into account'
                : (_lent ? 'Money leaves account' : 'Money goes into account'),
            iconKey: account?.iconKey,
            iconColor: account == null ? null : Color(account.colorValue),
            value: account?.name,
            placeholder: 'Choose account',
            onTap: () async {
              final r = await pickAccount(context, ref, selectedId: _accountId);
              if (r?.value != null) {
                setState(() {
                  _accountId = r!.value;
                  _accountTouched = true;
                });
              }
            },
          ),
          if (!_expected && !_isEdit) ...[
            const SizedBox(height: 14),
            AllocationChipField(
              label: _lent ? 'Whose money?' : 'Tag borrowed money as',
              amount: _amountPaisa,
              accountId: _accountId,
              value: _alloc,
              autoLabel: _lent ? 'Automatic' : 'Other money',
              onChanged: (v) => setState(() => _alloc = v),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Title (optional)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: _defaultTitle()),
          ),
          const SizedBox(height: 14),
          PickerField(
            label: _isEdit ? 'Current due date' : 'Due date',
            leading: const Icon(Icons.calendar_today_outlined),
            value: formatDate(_dueDate),
            onTap: _isEdit
                ? () => showMessage(
                    context,
                    'Use "Extend date" on the due to move the date.',
                  )
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dueDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _dueDate = d);
                  },
          ),
          const SizedBox(height: 14),
          const Text(
            'Reminder',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Default')),
              ButtonSegment(value: true, label: Text('Custom')),
            ],
            selected: {_customReminder},
            onSelectionChanged: (s) async {
              setState(() => _customReminder = s.first);
              if (s.first && _reminderAt == null) await _pickReminder();
            },
          ),
          if (_customReminder) ...[
            const SizedBox(height: 10),
            PickerField(
              label: '',
              leading: const Icon(Icons.notifications_none),
              value: _reminderAt == null ? null : formatDateTime(_reminderAt!),
              placeholder: 'Choose date and time',
              onTap: _pickReminder,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _repeat,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Repeat every N days until settled (optional)',
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Note',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.edit_outlined),
              hintText: 'Add a note',
            ),
          ),
          if (_isEdit && hasPayments)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'This due already has payments. Changing the amount keeps them.',
                style: TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit ? 'Save changes' : 'Save',
      ),
    );
  }
}
