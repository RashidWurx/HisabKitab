import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/icon_registry.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../data/transaction_repository.dart';
import '../domain/allocation_logic.dart';
import '../domain/transaction_models.dart';
import 'split_sheet.dart';

/// Add / edit an expense, income or transfer.
/// For editing, pass [transactionId] (the type is read from the record).
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({
    super.key,
    this.type,
    this.transactionId,
    this.prefillAmount,
    this.prefillCategoryId,
    this.prefillAccountId,
    this.fromAccountId,
    this.toAccountId,
  });

  final TransactionType? type;
  final String? transactionId;

  /// Optional pre-fill (reminders, savings shortcuts). Amount is in paisa.
  final int? prefillAmount;
  final String? prefillCategoryId;
  final String? prefillAccountId;
  final String? fromAccountId;
  final String? toAccountId;

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  late TransactionType _type = widget.type ?? TransactionType.expense;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  String? _sourceId; // single-source choice
  List<AllocationInput>? _split; // set when the user split the amount
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  bool _accountTouched = false;
  bool _sourceTouched = false;
  bool _acceptNegative = false;
  bool _loaded = false;
  bool _saving = false;
  TransactionInput? _original;

  bool get _isEdit => widget.transactionId != null;
  bool get _isTransfer => _type == TransactionType.transfer;
  bool get _isExpense => _type == TransactionType.expense;
  bool get _isIncome => _type == TransactionType.income;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _applyPrefill();
      _loaded = true;
    }
  }

  void _applyPrefill() {
    final w = widget;
    if (w.prefillAmount != null && w.prefillAmount! > 0) {
      _amount.text = Money.format(w.prefillAmount!)
          .replaceFirst('Rs ', '')
          .replaceAll(',', '');
    }
    if (w.prefillCategoryId != null) _categoryId = w.prefillCategoryId;
    if (w.prefillAccountId != null) {
      _accountId = w.prefillAccountId;
      _accountTouched = true;
    }
    if (w.fromAccountId != null) {
      _accountId = w.fromAccountId;
      _accountTouched = true;
    }
    if (w.toAccountId != null) _toAccountId = w.toAccountId;
  }

  Future<void> _load() async {
    final t = await ref
        .read(transactionRepositoryProvider)
        .get(widget.transactionId!);
    if (t == null || !mounted) {
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _original = t;
      _type = t.type;
      _amount.text = Money.format(t.amount)
          .replaceFirst('Rs ', '')
          .replaceAll(',', '');
      _note.text = t.note ?? '';
      _accountId = t.accountId;
      _toAccountId = t.toAccountId;
      _categoryId = t.categoryId;
      _date = t.date;
      _accountTouched = true;
      _sourceTouched = true;
      if (t.allocations.length == 1) {
        _sourceId = t.allocations.first.sourceId;
      } else {
        _split = t.allocations;
        _sourceId = t.allocations.first.sourceId;
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  // ---- derived values ------------------------------------------------------

  int get _amountPaisa => parseAmount(_amount.text) ?? 0;

  List<AllocationInput> get _allocations {
    if (_split != null) return _split!;
    if (_sourceId == null || _amountPaisa <= 0) return const [];
    return [AllocationInput(_sourceId!, _amountPaisa)];
  }

  bool get _splitStale =>
      _split != null && !allocationsValid(_split!, _amountPaisa);

  Map<AccountSource, int> get _balances => balancesWithout(
    ref.read(sourceBalancesProvider).value ?? const {},
    _original,
  );

  // ---- auto behaviour ------------------------------------------------------

  /// Re-runs the automatic account/source choice until the user overrides it.
  void _autoPick() {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final sources = ref.read(sourcesProvider).value ?? const <IncomeSource>[];
    final cats = ref.read(categoriesProvider).value ?? const <Category>[];
    Category? category;
    for (final c in cats) {
      if (c.id == _categoryId) category = c;
    }

    if (!_accountTouched && _isExpense) {
      final def = category?.defaultAccountId;
      final usable = accounts.where((a) => !a.isArchived).toList();
      if (def != null && usable.any((a) => a.id == def)) {
        _accountId = def;
      } else {
        _accountId ??= usable
            .where((a) => a.status == ActiveStatus.active)
            .map((a) => a.id)
            .firstOrNull;
      }
    }
    _accountId ??= accounts
        .where((a) => !a.isArchived && a.status == ActiveStatus.active)
        .map((a) => a.id)
        .firstOrNull;

    if (_sourceTouched || _isIncome || _accountId == null) return;
    Account? account;
    for (final a in accounts) {
      if (a.id == _accountId) account = a;
    }
    _sourceId = autoPickSource(
      balancesInAccount: LedgerService.sourcesInAccount(_balances, _accountId!),
      categoryDefaultSourceId: category?.defaultSourceId,
      accountDefaultSourceId: account?.defaultSpendingSourceId,
      fallbackSourceId: otherMoneySourceId,
    );
    // Archived / unknown source: fall back to Other money.
    if (!sources.any((s) => s.id == _sourceId)) {
      _sourceId = otherMoneySourceId;
    }
    _split = null;
  }

  // ---- actions -------------------------------------------------------------

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _openSplit() async {
    final accountId = _accountId;
    if (accountId == null) {
      showMessage(context, 'Choose an account first.');
      return;
    }
    if (_amountPaisa <= 0) {
      showMessage(context, 'Enter the amount first.');
      return;
    }
    final inAccount = LedgerService.sourcesInAccount(_balances, accountId);
    final initial = _allocations.isNotEmpty
        ? _split == null || _splitStale
              ? [
                  AllocationInput(
                    _sourceId ?? otherMoneySourceId,
                    _amountPaisa,
                  ),
                ]
              : _split!
        : [AllocationInput(_sourceId ?? otherMoneySourceId, _amountPaisa)];
    final result = await showSplitSheet(
      context,
      amount: _amountPaisa,
      initial: initial,
      balancesInAccount: inAccount,
      title: _isExpense ? 'Expense amount' : 'Amount',
    );
    if (result == null) return;
    setState(() {
      _sourceTouched = true;
      if (result.length == 1) {
        _sourceId = result.first.sourceId;
        _split = null;
      } else {
        _split = result;
        _sourceId = result.first.sourceId;
      }
    });
  }

  void _splitWithOthers() {
    final accountId = _accountId;
    if (accountId == null || _sourceId == null) return;
    final inAccount = LedgerService.sourcesInAccount(_balances, accountId);
    final result = splitWithOtherSources(
      primary: _sourceId!,
      amount: _amountPaisa,
      balancesInAccount: inAccount,
    );
    setState(() {
      _sourceTouched = true;
      if (result.length == 1) {
        _split = null;
      } else {
        _split = result;
      }
    });
  }

  Future<void> _save() async {
    final amount = _amountPaisa;
    final accountId = _accountId;
    if (amount <= 0) {
      showMessage(context, 'Enter an amount above 0.');
      return;
    }
    if (accountId == null) {
      showMessage(context, 'Choose an account.');
      return;
    }
    if (_isExpense && _categoryId == null) {
      showMessage(context, 'Choose a category.');
      return;
    }
    if (_isTransfer && _toAccountId == null) {
      showMessage(context, 'Choose the account to transfer to.');
      return;
    }
    if (_splitStale) {
      showMessage(context, 'The split no longer matches the amount. Fix the split first.');
      return;
    }
    var allocations = _allocations;
    if (_isIncome && allocations.isEmpty) {
      allocations = [AllocationInput(otherMoneySourceId, amount)];
    }

    // Warn (but allow) when something would go below zero.
    if (!_isIncome && !_acceptNegative) {
      final warning = _negativeWarning(amount, allocations);
      if (warning != null) {
        final ok = await confirmDialog(
          context,
          title: 'Not enough money',
          message: warning,
          confirmLabel: 'Save anyway',
        );
        if (!ok) return;
      }
    }

    final input = TransactionInput(
      id: widget.transactionId,
      type: _type,
      amount: amount,
      accountId: accountId,
      toAccountId: _isTransfer ? _toAccountId : null,
      categoryId: _isTransfer ? null : _categoryId,
      personId: _original?.personId,
      dueId: _original?.dueId,
      subscriptionId: _original?.subscriptionId,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: _original?.createdAt,
      allocations: allocations,
    );
    setState(() => _saving = true);
    try {
      await ref.read(transactionRepositoryProvider).save(input);
      if (mounted) context.pop();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _negativeWarning(int amount, List<AllocationInput> allocations) {
    final accountId = _accountId!;
    final b = _balances;
    final accountBalance = LedgerService.accountTotals(b)[accountId] ?? 0;
    if (accountBalance - amount < 0) {
      return 'This will take the account below Rs 0.';
    }
    for (final a in allocations) {
      final left = b[AccountSource(accountId, a.sourceId)] ?? 0;
      if (left - a.amount < 0) {
        return 'This source will go below Rs 0 in this account.';
      }
    }
    return null;
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete transaction?',
      message: 'This removes it from your balances.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(transactionRepositoryProvider);
    final snapshot = await repo.delete(widget.transactionId!);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    if (snapshot != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Transaction deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repo.save(snapshot),
            ),
          ),
        );
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Re-run automatic choices whenever data arrives or inputs change.
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    ref.watch(sourceBalancesProvider);
    final askSource =
        ref.watch(settingsProvider).value?.askSourceEachExpense ?? true;

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isEdit) _autoPick();

    final title = switch (_type) {
      TransactionType.expense => _isEdit ? 'Edit expense' : 'Add expense',
      TransactionType.income => _isEdit ? 'Edit income' : 'Add income',
      TransactionType.transfer => _isEdit ? 'Edit transfer' : 'Transfer',
      _ => 'Transaction',
    };

    Account? accountOf(String? id) {
      for (final a in accounts) {
        if (a.id == id) return a;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AmountField(
            controller: _amount,
            autofocus: !_isEdit,
            onChanged: (_) => setState(() {
              _acceptNegative = false;
              // One allocation follows the amount; a split must be fixed.
              if (_split == null) return;
            }),
          ),
          if (_splitStale)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The amount changed, so the source split no longer adds up. Tap the source below to fix the split.',
                style: TextStyle(color: context.appColors.negative),
              ),
            ),
          const SizedBox(height: 20),
          if (_isExpense) ...[
            const Text(
              'Category',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _categoryGrid(
              categories
                  .where((c) => c.kind == CategoryKind.expense && !c.isArchived)
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (_isTransfer) ..._transferFields(accountOf)
          else ...[
            PickerField(
              label: _isIncome ? 'Into account' : 'Account',
              iconKey: accountOf(_accountId)?.iconKey,
              iconColor: accountOf(_accountId) == null
                  ? null
                  : Color(accountOf(_accountId)!.colorValue),
              value: accountOf(_accountId)?.name,
              placeholder: 'Choose account',
              onTap: () async {
                final r = await pickAccount(
                  context,
                  ref,
                  selectedId: _accountId,
                );
                if (r?.value != null) {
                  setState(() {
                    _accountId = r!.value;
                    _accountTouched = true;
                    _acceptNegative = false;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            if (_isIncome)
              _incomeSourceField(sources)
            else if (askSource)
              _sourceChip(sources),
          ],
          if (_isExpense || _isTransfer) _shortfallBanner(sources),
          if (_isIncome) ...[
            const SizedBox(height: 16),
            PickerField(
              label: 'Category (optional)',
              value: _categoryName(categories),
              placeholder: 'None',
              onTap: () async {
                final r = await pickCategory(
                  context,
                  ref,
                  kind: CategoryKind.income,
                  selectedId: _categoryId,
                  allowNone: true,
                );
                if (r != null) setState(() => _categoryId = r.value);
              },
            ),
          ],
          const SizedBox(height: 16),
          PickerField(
            label: 'Date',
            leading: const Icon(Icons.calendar_today_outlined, size: 22),
            value: DateFormat('d MMM y').format(_date),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
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
          if (_isExpense) _afterPreview(sources),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _splitStale ? null : _save,
            child: Text(switch (_type) {
              TransactionType.expense => _isEdit ? 'Save changes' : 'Save expense',
              TransactionType.income => _isEdit ? 'Save changes' : 'Save income',
              _ => _isEdit ? 'Save changes' : 'Save transfer',
            }),
          ),
        ],
      ),
    );
  }

  String? _categoryName(List<Category> cats) {
    for (final c in cats) {
      if (c.id == _categoryId) return c.name;
    }
    return null;
  }

  Widget _categoryGrid(List<Category> cats) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 3 * 8) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats)
              SizedBox(
                width: width,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    _categoryId = c.id;
                    _accountTouched = false;
                    _sourceTouched = false;
                    _acceptNegative = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _categoryId == c.id
                          ? AppTheme.navy
                          : scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          iconFor(c.iconKey),
                          color: _categoryId == c.id ? Colors.white : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _categoryId == c.id ? Colors.white : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _sourceSummary(List<IncomeSource> sources) {
    String name(String id) {
      for (final s in sources) {
        if (s.id == id) return s.name;
      }
      return 'Unknown';
    }

    final allocs = _allocations;
    if (_split != null && allocs.length > 1) {
      return 'Split: ${allocs.map((a) => '${name(a.sourceId)} ${Money.format(a.amount)}').join(' + ')}';
    }
    return name(_sourceId ?? otherMoneySourceId);
  }

  /// "Whose money" chip under the account field (tap to change or split).
  Widget _sourceChip(List<IncomeSource> sources) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final accountId = _accountId;
        if (accountId == null) {
          showMessage(context, 'Choose an account first.');
          return;
        }
        final inAccount = LedgerService.sourcesInAccount(_balances, accountId);
        final r = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Choose one source'),
                  onTap: () => Navigator.pop(ctx, 'one'),
                ),
                ListTile(
                  leading: const Icon(Icons.call_split),
                  title: const Text('Split across sources'),
                  onTap: () => Navigator.pop(ctx, 'split'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || r == null) return;
        if (r == 'split') {
          await _openSplit();
        } else {
          final pick = await pickSource(
            context,
            ref,
            selectedId: _sourceId,
            balances: inAccount,
            title: 'Whose money?',
          );
          if (pick?.value != null) {
            setState(() {
              _sourceId = pick!.value;
              _split = null;
              _sourceTouched = true;
              _acceptNegative = false;
            });
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
          color: scheme.surfaceContainerLowest,
        ),
        child: Row(
          children: [
            const Icon(Icons.sell_outlined, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _sourceSummary(sources),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.edit_outlined, size: 20),
          ],
        ),
      ),
    );
  }

  /// Income: optional source; the account follows the source's linked one.
  Widget _incomeSourceField(List<IncomeSource> sources) {
    return PickerField(
      label: 'From source (optional)',
      iconKey: 'work',
      value: _sourceId == null
          ? null
          : (sources.where((s) => s.id == _sourceId).firstOrNull?.name),
      placeholder: 'None (Other money)',
      onTap: () async {
        final r = await pickSource(
          context,
          ref,
          selectedId: _sourceId,
          allowNone: true,
        );
        if (r == null) return;
        setState(() {
          _sourceId = r.value;
          _sourceTouched = true;
          final linked = sources
              .where((s) => s.id == r.value)
              .firstOrNull
              ?.linkedAccountId;
          if (linked != null && !_accountTouched) _accountId = linked;
        });
      },
    );
  }

  Widget _shortfallBanner(List<IncomeSource> sources) {
    final accountId = _accountId;
    if (accountId == null ||
        _sourceId == null ||
        _split != null ||
        _amountPaisa <= 0) {
      return const SizedBox.shrink();
    }
    final inAccount = LedgerService.sourcesInAccount(_balances, accountId);
    final short = shortfall(
      sourceBalance: inAccount[_sourceId] ?? 0,
      amount: _amountPaisa,
    );
    if (short == 0 || _acceptNegative) {
      return _acceptNegative && short > 0
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This source will go negative in this account.',
                style: TextStyle(color: context.appColors.negative),
              ),
            )
          : const SizedBox.shrink();
    }
    final name =
        sources.where((s) => s.id == _sourceId).firstOrNull?.name ?? 'Source';
    final red = context.appColors.negative;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: red),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name is short by ${Money.format(short)} in this account.',
              style: TextStyle(color: red, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: _splitWithOthers,
                    child: const Text('Split with another source'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _acceptNegative = true),
                  child: const Text('Save anyway'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Account after expense / Source after expense" preview.
  Widget _afterPreview(List<IncomeSource> sources) {
    final accountId = _accountId;
    if (accountId == null || _amountPaisa <= 0) {
      return const SizedBox.shrink();
    }
    final b = _balances;
    final accountAfter =
        (LedgerService.accountTotals(b)[accountId] ?? 0) - _amountPaisa;
    final allocs = _allocations;
    int? sourceAfter;
    if (allocs.length == 1) {
      sourceAfter =
          (b[AccountSource(accountId, allocs.first.sourceId)] ?? 0) -
          allocs.first.amount;
    }
    TextStyle style = const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          InfoRow(
            'Account after expense',
            null,
            valueWidget: MoneyText(accountAfter, neutral: accountAfter >= 0, style: style),
          ),
          if (sourceAfter != null)
            InfoRow(
              'Source after expense',
              null,
              valueWidget: MoneyText(
                sourceAfter,
                neutral: sourceAfter >= 0,
                style: style,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _transferFields(Account? Function(String?) accountOf) {
    final scheme = Theme.of(context).colorScheme;
    final sources = ref.read(sourcesProvider).value ?? const <IncomeSource>[];
    final from = accountOf(_accountId);
    final to = accountOf(_toAccountId);
    return [
      PickerField(
        label: 'From',
        iconKey: from?.iconKey,
        iconColor: from == null ? null : Color(from.colorValue),
        value: from?.name,
        placeholder: 'Choose account',
        onTap: () async {
          final r = await pickAccount(
            context,
            ref,
            selectedId: _accountId,
            excludeId: _toAccountId,
            title: 'From account',
          );
          if (r?.value != null) {
            setState(() {
              _accountId = r!.value;
              _accountTouched = true;
              _sourceTouched = false;
              _acceptNegative = false;
            });
          }
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const Icon(Icons.arrow_downward, size: 20),
          ),
        ),
      ),
      PickerField(
        label: 'To',
        iconKey: to?.iconKey,
        iconColor: to == null ? null : Color(to.colorValue),
        value: to?.name,
        placeholder: 'Choose account',
        onTap: () async {
          final r = await pickAccount(
            context,
            ref,
            selectedId: _toAccountId,
            excludeId: _accountId,
            title: 'To account',
          );
          if (r?.value != null) setState(() => _toAccountId = r!.value);
        },
      ),
      const SizedBox(height: 16),
      const Text(
        'Source',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      _sourceChip(sources),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'This money keeps its source in ${to?.name ?? 'the new account'}.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      ),
    ];
  }
}
