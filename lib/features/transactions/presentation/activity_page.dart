import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../ledger/data/ledger_service.dart';
import '../data/transaction_repository.dart';
import 'open_transaction.dart';
import 'transaction_tile.dart';

const _typeLabels = {
  TransactionType.expense: 'Expense',
  TransactionType.income: 'Income',
  TransactionType.transfer: 'Transfer',
  TransactionType.lendOut: 'Lent',
  TransactionType.borrowIn: 'Borrowed',
  TransactionType.repayIn: 'Repaid to me',
  TransactionType.repayOut: 'I repaid',
  TransactionType.passIn: '3rd party in',
  TransactionType.passOut: '3rd party out',
};

class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key, this.initialFilter});

  final TransactionFilter? initialFilter;

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  late TransactionFilter _filter =
      widget.initialFilter ?? const TransactionFilter();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _dayHeader(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(d);
    final diff = today.difference(day).inDays;
    final date = DateFormat('d MMM').format(d);
    if (diff == 0) return 'Today • $date';
    if (diff == 1) return 'Yesterday • $date';
    return '${DateFormat('EEEE').format(d)} • $date';
  }

  Future<void> _delete(Transaction t) async {
    final repo = ref.read(transactionRepositoryProvider);
    final snapshot = await repo.delete(t.id);
    if (!mounted || snapshot == null) return;
    ScaffoldMessenger.of(context)
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

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(transactionsProvider(_filter));
    final accounts = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };
    final categories = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };
    final activeFilters = _filter.copyWith(search: '');
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) =>
                        setState(() => _filter = _filter.copyWith(search: v)),
                    decoration: InputDecoration(
                      hintText: 'Search transactions',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _search.clear();
                                _filter = _filter.copyWith(search: '');
                              }),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: !activeFilters.isEmpty,
                    child: const Icon(Icons.filter_alt_outlined),
                  ),
                  label: const Text('Filter'),
                ),
              ],
            ),
          ),
          Expanded(
            child: txs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Something went wrong: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: _filter.isEmpty
                        ? 'No transactions yet'
                        : 'Nothing matches',
                    message: _filter.isEmpty
                        ? 'Add your first expense or income and it will show up here.'
                        : 'Try changing or clearing the filters.',
                    actionLabel: _filter.isEmpty ? 'Add expense' : 'Clear filters',
                    onAction: _filter.isEmpty
                        ? () => context.push('/transaction/new/expense')
                        : () => setState(() {
                            _search.clear();
                            _filter = const TransactionFilter();
                          }),
                  );
                }
                return _grouped(list, accounts, categories);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _grouped(
    List<Transaction> list,
    Map<String, Account> accounts,
    Map<String, Category> categories,
  ) {
    // Flat list (day headers + transactions) so only visible rows are built.
    final items = <Object>[];
    DateTime? currentDay;
    var group = <Transaction>[];
    void flush() {
      if (currentDay == null) return;
      items.add((currentDay, LedgerService.dayNet(group)));
      items.addAll(group);
      group = [];
    }

    for (final t in list) {
      final day = DateUtils.dateOnly(t.date);
      if (currentDay != null && day != currentDay) flush();
      currentDay = day;
      group.add(t);
    }
    flush();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 128),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is (DateTime, int)) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dayHeader(item.$1),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (item.$2 != 0)
                  MoneyText(
                    item.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          );
        }
        final t = item as Transaction;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.error,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onError,
                ),
              ),
              confirmDismiss: (_) async {
                if (t.type == TransactionType.passIn ||
                    t.type == TransactionType.passOut) {
                  showMessage(
                    context,
                    'This is 3rd party money. Open the record to change it.',
                  );
                  return false;
                }
                if (t.dueId != null) {
                  showMessage(
                    context,
                    'This belongs to a due. Open the due to change or delete it.',
                  );
                  return false;
                }
                return true;
              },
              onDismissed: (_) => _delete(t),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TransactionTile(
                  transaction: t,
                  accounts: accounts,
                  categories: categories,
                  onTap: () => openTransaction(context, ref, t),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final TransactionFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TransactionFilter f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final sources = ref.watch(sourcesProvider).value ?? const <IncomeSource>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    String? name<T>(Iterable<T> items, String? id, String Function(T) idOf, String Function(T) nameOf) {
      for (final i in items) {
        if (idOf(i) == id) return nameOf(i);
      }
      return null;
    }

    final fmt = DateFormat('d MMM y');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => f = TransactionFilter(search: widget.initial.search),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _typeLabels.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: f.types.contains(entry.key),
                  onSelected: (on) {
                    final next = {...f.types};
                    on ? next.add(entry.key) : next.remove(entry.key);
                    setState(() => f = f.copyWith(types: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Account',
            value: name<Account>(accounts, f.accountId, (a) => a.id, (a) => a.name),
            placeholder: 'Any account',
            onTap: () async {
              final r = await pickAccount(
                context,
                ref,
                selectedId: f.accountId,
                allowNone: true,
              );
              if (r != null) setState(() => f = f.copyWith(accountId: r.value));
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Source',
            value: name<IncomeSource>(sources, f.sourceId, (s) => s.id, (s) => s.name),
            placeholder: 'Any source',
            onTap: () async {
              final r = await pickSource(
                context,
                ref,
                selectedId: f.sourceId,
                allowNone: true,
              );
              if (r != null) setState(() => f = f.copyWith(sourceId: r.value));
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Category',
            value: name<Category>(cats, f.categoryId, (c) => c.id, (c) => c.name),
            placeholder: 'Any category',
            onTap: () async {
              final all = await showItemPicker<String>(
                context,
                title: 'Category',
                selected: f.categoryId,
                noneLabel: 'Any category',
                items: [
                  for (final c in cats)
                    PickerItem(
                      value: c.id,
                      title:
                          '${c.name} (${c.kind == CategoryKind.expense ? 'expense' : 'income'})',
                      iconKey: c.iconKey,
                      color: Color(c.colorValue),
                    ),
                ],
              );
              if (all != null) setState(() => f = f.copyWith(categoryId: all.value));
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Date range',
            leading: const Icon(Icons.date_range_outlined),
            value: f.from == null && f.to == null
                ? null
                : '${f.from == null ? '…' : fmt.format(f.from!)} – ${f.to == null ? '…' : fmt.format(f.to!.subtract(const Duration(days: 1)))}',
            placeholder: 'Any date',
            onTap: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (r != null) {
                setState(
                  () => f = f.copyWith(
                    from: DateUtils.dateOnly(r.start),
                    to: DateUtils.dateOnly(r.end).add(const Duration(days: 1)),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context, f),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
