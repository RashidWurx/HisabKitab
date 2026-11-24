import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/manager_list.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../transactions/data/transaction_repository.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Categories'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Expense'),
                Tab(text: 'Income'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              final kind = DefaultTabController.of(context).index == 0
                  ? 'expense'
                  : 'income';
              context.push('/categories/new?kind=$kind');
            },
            child: const Icon(Icons.add),
          ),
          body: TabBarView(
            children: [
              for (final kind in CategoryKind.values)
                ManagedList(
                  items: [
                    for (final c in all.where((c) => c.kind == kind))
                      ManagedItem(
                        id: c.id,
                        title: c.name,
                        iconKey: c.iconKey,
                        color: Color(c.colorValue),
                        archived: c.isArchived,
                      ),
                  ],
                  emptyTitle: 'No ${kind.name} categories',
                  emptyMessage: 'Add one to start organising your money.',
                  addLabel: 'Add category',
                  onAdd: () => context.push('/categories/new?kind=${kind.name}'),
                  onOpen: (id) => context.push('/categories/$id/edit'),
                  onReorder: ref.read(categoryRepositoryProvider).reorder,
                  onAction: (id, action) async {
                    final repo = ref.read(categoryRepositoryProvider);
                    switch (action) {
                      case ManagedAction.edit:
                        context.push('/categories/$id/edit');
                      case ManagedAction.archive:
                        await repo.setArchived(id, true);
                      case ManagedAction.unarchive:
                        await repo.setArchived(id, false);
                      case ManagedAction.delete:
                        await _deleteFlow(context, ref, id, kind);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteFlow(
    BuildContext context,
    WidgetRef ref,
    String id,
    CategoryKind kind,
  ) async {
    final repo = ref.read(categoryRepositoryProvider);
    String? moveTo;
    final used = await repo.usageCount(id);
    if (!context.mounted) return;
    if (used > 0) {
      final pick = await pickCategory(
        context,
        ref,
        kind: kind,
        excludeId: id,
        title: 'Move its transactions to',
      );
      moveTo = pick?.value;
      if (moveTo == null || !context.mounted) return;
    } else {
      final ok = await confirmDialog(
        context,
        title: 'Delete category?',
        message: 'This cannot be undone.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await repo.delete(id, moveToId: moveTo);
      if (context.mounted) showMessage(context, 'Category deleted');
    } on LedgerException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}
