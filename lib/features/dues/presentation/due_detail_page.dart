import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/due_repository.dart';
import '../domain/due_models.dart';
import 'due_widgets.dart';
import 'extend_sheet.dart';
import 'payment_sheet.dart';

class DueDetailPage extends ConsumerWidget {
  const DueDetailPage({super.key, required this.dueId});

  final String dueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(dueViewProvider(dueId)).value;
    if (view == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final events = ref.watch(dueEventsProvider(dueId)).value ?? const [];
    final accounts = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };
    final people = {
      for (final p in ref.watch(peopleProvider).value ?? const <PeopleData>[])
        p.id: p,
    };
    final sources = {
      for (final s in ref.watch(sourcesProvider).value ?? const <IncomeSource>[])
        s.id: s,
    };
    final d = view.due;
    final colors = context.appColors;
    final receiving = view.isReceivable;
    final who = people[d.personId]?.name;
    final sourceName = sources[d.sourceId]?.name;
    final remainingColor = view.remaining == 0
        ? null
        : (view.status == DueStatus.overdue
              ? colors.negative
              : (receiving ? colors.positive : colors.negative));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Due detail'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, ref, view, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'note', child: Text('Add note')),
              if (view.isOpen) ...[
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'snooze', child: Text('Snooze reminder')),
                const PopupMenuItem(value: 'cancel', child: Text('Cancel due')),
              ],
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (who != null || sourceName != null)
                      Text(
                        who ?? sourceName!,
                        style: const TextStyle(fontSize: 17),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DueStatusChip(view.status),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                InfoRow(
                  'Remaining',
                  null,
                  valueWidget: Text(
                    Money.format(view.remaining),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: remainingColor,
                    ),
                  ),
                ),
                const Divider(),
                InfoRow('Total', Money.format(view.total)),
                const Divider(),
                InfoRow(
                  receiving ? 'Received' : 'Paid',
                  null,
                  valueWidget: Text(
                    Money.format(view.paid),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: view.paid == 0
                          ? null
                          : (receiving ? colors.positive : colors.negative),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                InfoRow('Original date', formatDateShort(d.originalDueDate)),
                const Divider(),
                InfoRow('Current date', formatDateShort(d.currentDueDate)),
                const Divider(),
                InfoRow('Extended', '${view.extensionCount}×'),
                if (view.lateDays > 0 && view.status != DueStatus.cancelled) ...[
                  const Divider(),
                  InfoRow(
                    'Late by',
                    null,
                    valueWidget: Text(
                      '${view.lateDays} days',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.negative,
                      ),
                    ),
                  ),
                ],
                const Divider(),
                InfoRow(
                  receiving ? 'Into account' : 'Account',
                  accounts[d.accountId]?.name ?? '-',
                ),
                if (d.note != null && d.note!.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(d.note!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Activity'),
          _Timeline(events: events, accounts: accounts, view: view),
          if (view.isOpen) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showPaymentSheet(context, ref, view),
                    child: Text(receiving ? 'Mark received' : 'Mark paid'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => showExtendSheet(context, ref, view),
                    child: const Text('Extend date'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    DueView view,
    String action,
  ) async {
    final repo = ref.read(dueRepositoryProvider);
    final id = view.due.id;
    switch (action) {
      case 'note':
        final text = await _askText(context, 'Add note', hint: 'e.g. Called him, he will pay Friday');
        if (text != null && context.mounted) {
          await _guard(context, () => repo.addNote(id, text));
        }
      case 'edit':
        context.push('/dues/$id/edit');
      case 'snooze':
        await _snooze(context, repo, id);
      case 'cancel':
        await _cancel(context, repo, view);
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete this due?',
          message:
              'Its history and every payment linked to it will be removed, and your balances will change. This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) {
          await repo.delete(id);
          if (context.mounted) context.pop();
        }
    }
  }

  Future<void> _snooze(BuildContext context, DueRepository repo, String id) async {
    final now = DateTime.now();
    DateTime at(int days, int hour) =>
        DateTime(now.year, now.month, now.day + days, hour);
    final choice = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('In 3 hours'),
              onTap: () => Navigator.pop(ctx, now.add(const Duration(hours: 3))),
            ),
            ListTile(
              title: const Text('Tomorrow, 9:00 AM'),
              onTap: () => Navigator.pop(ctx, at(1, 9)),
            ),
            ListTile(
              title: const Text('In 3 days, 9:00 AM'),
              onTap: () => Navigator.pop(ctx, at(3, 9)),
            ),
            ListTile(
              title: const Text('Next week, 9:00 AM'),
              onTap: () => Navigator.pop(ctx, at(7, 9)),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await repo.snooze(id, choice);
  }

  Future<void> _cancel(BuildContext context, DueRepository repo, DueView view) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this due?'),
        content: Text(
          view.remaining > 0
              ? '${Money.format(view.remaining)} is still outstanding. Write it off, or just close the due?'
              : 'This will close the due.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
          if (view.remaining > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: const Text('Close, not written off'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'writeoff'),
            child: Text(view.remaining > 0 ? 'Write off' : 'Cancel due'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await repo.cancel(view.due.id, writeOff: choice == 'writeoff');
    }
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() fn) async {
  try {
    await fn();
  } on LedgerException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

Future<String?> _askText(
  BuildContext context,
  String title, {
  String initial = '',
  String? hint,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// History, newest on top, with the date and time of each entry.
class _Timeline extends ConsumerWidget {
  const _Timeline({
    required this.events,
    required this.accounts,
    required this.view,
  });

  final List<DueEvent> events;
  final Map<String, Account> accounts;
  final DueView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final receiving = view.isReceivable;
    final colors = context.appColors;
    if (events.isEmpty) return const Text('No history yet.');
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    children: [
                      Container(
                        width: 3,
                        height: 8,
                        color: i == 0 ? Colors.transparent : scheme.onSurface,
                      ),
                      Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 3,
                          color: i == events.length - 1
                              ? Colors.transparent
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _entry(context, ref, events[i], scheme, colors, receiving),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    WidgetRef ref,
    DueEvent e,
    ColorScheme scheme,
    AppColors colors,
    bool receiving,
  ) {
    String title;
    String? detail;
    switch (e.type) {
      case DueEventType.created:
        title = 'Created';
        detail = e.amount == null ? null : Money.format(e.amount!);
      case DueEventType.payment:
        title = receiving ? 'Payment received' : 'Payment made';
        detail =
            '${Money.format(e.amount ?? 0)} ${receiving ? 'into' : 'from'} ${accounts[e.accountId]?.name ?? 'account'}';
      case DueEventType.extended:
        title = 'Date extended';
        detail =
            '${e.oldDate == null ? '' : formatDateShort(e.oldDate!)} → ${e.newDate == null ? '' : formatDateShort(e.newDate!)}'
            '${e.reason == null ? '' : '\n${e.reason}'}';
      case DueEventType.note:
        title = 'Note${e.editedAt == null ? '' : ' (edited)'}';
        detail = e.note;
      case DueEventType.reminderChanged:
        title = 'Reminder changed';
        detail = e.note;
      case DueEventType.amountEdited:
        title = 'Amount edited';
        detail = e.note;
      case DueEventType.cancelled:
        title = 'Cancelled';
        detail = e.note;
      case DueEventType.settled:
        title = 'Settled';
      case DueEventType.paymentEdited:
        title = 'Payment edited';
        detail = e.note;
      case DueEventType.paymentDeleted:
        title = 'Payment removed';
        detail = e.note;
    }
    final canManage = e.type == DueEventType.payment && e.transactionId != null;
    final isNote = e.type == DueEventType.note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDateTime(e.at),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (detail != null && detail.isNotEmpty) Text(detail),
            ],
          ),
        ),
        if (canManage)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) async {
              final repo = ref.read(dueRepositoryProvider);
              if (v == 'edit') {
                final text = await _askAmount(context, e.amount ?? 0);
                if (text != null && context.mounted) {
                  await _guard(
                    context,
                    () => repo.editPayment(e.transactionId!, amount: text),
                  );
                }
              } else {
                final ok = await confirmDialog(
                  context,
                  title: 'Delete payment?',
                  message: 'The due will be updated and this is added to its history.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (ok) await repo.deletePayment(e.transactionId!);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit amount')),
              PopupMenuItem(value: 'delete', child: Text('Delete payment')),
            ],
          ),
        if (isNote)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final text = await _askText(
                context,
                'Edit note',
                initial: e.note ?? '',
              );
              if (text != null && context.mounted) {
                await _guard(
                  context,
                  () => ref.read(dueRepositoryProvider).editNote(e.id, text),
                );
              }
            },
          ),
      ],
    );
  }

  Future<int?> _askAmount(BuildContext context, int current) async {
    final controller = TextEditingController(
      text: Money.format(current).replaceFirst('Rs ', '').replaceAll(',', ''),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit payment amount'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountFormatters,
          decoration: const InputDecoration(prefixText: 'Rs '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, parseAmount(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
