import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/manager_list.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/account_repository.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final balances = LedgerService.accountTotals(
      ref.watch(sourceBalancesProvider).value ?? const {},
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/accounts/new'),
        child: const Icon(Icons.add),
      ),
      body: ManagedList(
        items: [
          for (final a in accounts)
            ManagedItem(
              id: a.id,
              title: a.name,
              subtitle: _typeLabel(a.type),
              iconKey: a.iconKey,
              color: Color(a.colorValue),
              badge: a.status == ActiveStatus.inactive ? 'Inactive' : null,
              archived: a.isArchived,
              trailing: MoneyText(
                balances[a.id] ?? 0,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
        emptyTitle: 'No accounts yet',
        emptyMessage:
            'Add the places your money sits: a bank, a wallet, cash in hand.',
        addLabel: 'Add account',
        onAdd: () => context.push('/accounts/new'),
        onOpen: (id) => context.push('/accounts/$id'),
        onReorder: ref.read(accountRepositoryProvider).reorder,
        onAction: (id, action) => _onAction(context, ref, id, action),
      ),
    );
  }

  static String _typeLabel(AccountType t) => switch (t) {
    AccountType.bank => 'Bank',
    AccountType.mobileWallet => 'Mobile wallet',
    AccountType.cash => 'Cash',
    AccountType.onlineWallet => 'Online wallet',
    AccountType.savings => 'Savings',
    AccountType.other => 'Other',
  };

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String id,
    ManagedAction action,
  ) async {
    final repo = ref.read(accountRepositoryProvider);
    switch (action) {
      case ManagedAction.edit:
        context.push('/accounts/$id/edit');
      case ManagedAction.archive:
        await repo.setArchived(id, true);
      case ManagedAction.unarchive:
        await repo.setArchived(id, false);
      case ManagedAction.delete:
        await deleteAccountFlow(context, ref, id);
    }
  }
}

/// Delete an account, or (if it has transactions) offer to archive it or
/// move its transactions to another account first.
Future<void> deleteAccountFlow(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final repo = ref.read(accountRepositoryProvider);
  final ok = await confirmDialog(
    context,
    title: 'Delete account?',
    message: 'This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await repo.delete(id);
    if (context.mounted) showMessage(context, 'Account deleted');
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
            child: const Text('Move transactions'),
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
      final target = await pickAccount(
        context,
        ref,
        excludeId: id,
        title: 'Move transactions to',
      );
      if (target?.value == null) return;
      try {
        await repo.moveTransactions(id, target!.value!);
        await repo.delete(id);
        if (context.mounted) showMessage(context, 'Moved and deleted');
      } on LedgerException catch (e) {
        if (context.mounted) showMessage(context, e.message);
      }
    }
  }
}

/// Used by other screens that need a formatted balance string.
String formatBalance(int paisa) => Money.format(paisa);
