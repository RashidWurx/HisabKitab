import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/providers.dart';
import '../../../core/ui/manager_list.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../ledger/data/ledger_service.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';

class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final totals = LedgerService.sourceTotals(
      ref.watch(sourceBalancesProvider).value ?? const {},
    );
    String? accountName(String? id) {
      for (final a in accounts) {
        if (a.id == id) return a.name;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Income sources')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/sources/new'),
        child: const Icon(Icons.add),
      ),
      body: ManagedList(
        items: [
          for (final s in sources)
            ManagedItem(
              id: s.id,
              title: s.name,
              subtitle: s.isBuiltIn
                  ? 'Money with no real source'
                  : accountName(s.linkedAccountId) == null
                  ? 'No linked account'
                  : 'Pays into ${accountName(s.linkedAccountId)}',
              iconKey: s.iconKey,
              color: Color(s.colorValue),
              badge: s.status == ActiveStatus.inactive ? 'Inactive' : null,
              archived: s.isArchived,
              locked: s.isBuiltIn,
              trailing: MoneyText(
                totals[s.id] ?? 0,
                neutral: true,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
        emptyTitle: 'No income sources yet',
        emptyMessage:
            'Add where your money comes from: a job, freelancing, a business.',
        addLabel: 'Add source',
        onAdd: () => context.push('/sources/new'),
        onOpen: (id) => context.push('/sources/$id'),
        onReorder: ref.read(sourceRepositoryProvider).reorder,
        onAction: (id, action) async {
          final repo = ref.read(sourceRepositoryProvider);
          switch (action) {
            case ManagedAction.edit:
              context.push('/sources/$id/edit');
            case ManagedAction.archive:
              await repo.setArchived(id, true);
            case ManagedAction.unarchive:
              await repo.setArchived(id, false);
            case ManagedAction.delete:
              await deleteSourceFlow(context, ref, id);
          }
        },
      ),
    );
  }
}

/// Delete a source, or (if money is tagged to it) offer to archive it or
/// move its money to another source / "Other money".
Future<void> deleteSourceFlow(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final repo = ref.read(sourceRepositoryProvider);
  final ok = await confirmDialog(
    context,
    title: 'Delete source?',
    message: 'This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await repo.delete(id);
    if (context.mounted) showMessage(context, 'Source deleted');
  } on BlockedDeleteException catch (e) {
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot delete'),
        content: Text(e.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'move'),
            child: const Text('Move money'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'archive'),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (choice == 'archive') {
      await repo.setArchived(id, true);
    } else if (choice == 'move' && context.mounted) {
      final target = await pickSource(
        context,
        ref,
        title: 'Move its money to',
        exclude: {id},
      );
      final toId = target?.value;
      if (toId == null) return;
      try {
        await repo.moveAllocations(id, toId);
        await repo.delete(id);
        if (context.mounted) showMessage(context, 'Moved and deleted');
      } on LedgerException catch (e) {
        if (context.mounted) showMessage(context, e.message);
      }
    }
  }
}

/// Convenience for screens that need to know if a source is the built-in one.
bool isOtherMoney(String id) => id == otherMoneySourceId;
