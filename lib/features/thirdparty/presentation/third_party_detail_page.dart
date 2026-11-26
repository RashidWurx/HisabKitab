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
import '../domain/pass_models.dart';
import 'pass_widgets.dart';

/// One 3rd party record: what is left on each side, the next steps and the
/// complete history.
class ThirdPartyDetailPage extends ConsumerWidget {
  const ThirdPartyDetailPage({super.key, required this.passId});

  final String passId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(passViewsProvider).value;
    final people = ref.watch(peopleProvider).value ?? const <PeopleData>[];
    // Keep account balances loaded for the account picker in the sheet.
    ref.watch(accountsProvider);
    ref.watch(sourceBalancesProvider);
    final v = views?.where((x) => x.pass.id == passId).firstOrNull;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: views == null
              ? const CircularProgressIndicator()
              : const Text('This record no longer exists.'),
        ),
      );
    }
    final names = PassNames.of(v, people);
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('d MMM y');
    final actions = [
      for (final a in PassAction.values)
        if (v.maxFor(a) > 0) a,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${names.lender} → ${names.receiver}'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/third-party/$passId/edit'),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Delete this record?',
                message:
                    'Its history is removed and any money it moved through your accounts is undone.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              final repo = ref.read(passRepositoryProvider);
              context.pop();
              await repo.delete(passId);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          AppCard(
            child: Column(
              children: [
                InfoRow('Amount', Money.format(v.amount)),
                if (v.toHandOver > 0) ...[
                  const Divider(),
                  InfoRow(
                    'Still to give ${names.receiver}',
                    Money.format(v.toHandOver),
                  ),
                ],
                const Divider(),
                InfoRow(
                  'To collect',
                  null,
                  valueWidget: MoneyText(v.toCollect, style: _value),
                ),
                const Divider(),
                InfoRow(
                  'To return',
                  null,
                  valueWidget: MoneyText(-v.toPayBack, style: _value),
                ),
                if (v.pass.collectBy != null) ...[
                  const Divider(),
                  InfoRow('Collect by', date.format(v.pass.collectBy!)),
                ],
                if (v.pass.returnBy != null) ...[
                  const Divider(),
                  InfoRow('Return by', date.format(v.pass.returnBy!)),
                ],
              ],
            ),
          ),
          if (v.holding > 0 || v.covered > 0) ...[
            const SizedBox(height: 10),
            InlineEmpty(
              Icons.info_outline,
              v.covered > 0
                  ? 'You have paid ${Money.format(v.covered)} from your own money. ${names.receiver} owes it to you.'
                  : 'You are holding ${Money.format(v.holding)} of this money. It is not part of your total balance.',
            ),
          ],
          if (v.pass.note != null) ...[
            const SizedBox(height: 10),
            Text(v.pass.note!),
          ],
          if (actions.isNotEmpty) ...[
            const SectionTitle('Record what happened'),
            for (final a in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          _ActionSheet(view: v, action: a, names: names),
                    ),
                    child: Text(names.actionLabel(a)),
                  ),
                ),
              ),
          ],
          const SectionTitle('History'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < v.entries.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(
                      names.entryLabel(v.entries[i].kind),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        date.format(v.entries[i].date),
                        Money.format(v.entries[i].amount),
                        if (v.entries[i].note != null) v.entries[i].note!,
                      ].join(' · '),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    trailing:
                        v.entries[i].kind == PassEntryKind.takenIn ||
                            v.entries[i].kind == PassEntryKind.lentDirect
                        ? null
                        : IconButton(
                            tooltip: 'Remove this step',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                _removeStep(context, ref, v.entries[i].id),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeStep(
    BuildContext context,
    WidgetRef ref,
    String entryId,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove this step?',
      message: 'Any money it moved through your account is undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(passRepositoryProvider).deleteEntry(entryId);
    } on LedgerException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}

const _value = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

class _ActionSheet extends ConsumerStatefulWidget {
  const _ActionSheet({
    required this.view,
    required this.action,
    required this.names,
  });

  final PassView view;
  final PassAction action;
  final PassNames names;

  @override
  ConsumerState<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends ConsumerState<_ActionSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Money.format(widget.view.maxFor(widget.action))
        .replaceFirst('Rs ', '')
        .replaceAll(',', ''),
  );
  final _note = TextEditingController();
  String? _accountId;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  bool get _usesAccount => widget.action != PassAction.direct;

  @override
  void initState() {
    super.initState();
    // Start with the account this record last used.
    final tx = widget.view.entries
        .map((e) => e.transactionId)
        .nonNulls
        .firstOrNull;
    if (tx != null) {
      ref.read(transactionRepositoryProvider).get(tx).then((t) {
        if (mounted && _accountId == null) {
          setState(() => _accountId = t?.accountId);
        }
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(passRepositoryProvider)
          .record(
            widget.view.pass.id,
            widget.action,
            amount: parseAmount(_amount.text) ?? 0,
            accountId: _usesAccount ? _accountId : null,
            date: _date,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context);
    } on LedgerException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A dialog, because a snackbar would be hidden behind this sheet.
  void _showError(String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.names.actionLabel(widget.action),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            AmountField(controller: _amount, autofocus: false),
            const SizedBox(height: 16),
            if (_usesAccount) ...[
              PickerField(
                label: widget.action == PassAction.collect
                    ? 'Into my account'
                    : 'From my account',
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
              const SizedBox(height: 16),
            ],
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
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
