import 'package:material_ui/material_ui.dart';

import 'widgets.dart';

class ManagedItem {
  const ManagedItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.iconKey,
    required this.color,
    this.badge,
    this.archived = false,
    this.locked = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String iconKey;
  final Color color;

  /// Small label such as "Inactive".
  final String? badge;
  final bool archived;

  /// Built-in items cannot be archived or deleted.
  final bool locked;
}

enum ManagedAction { edit, archive, unarchive, delete }

/// Reorderable list of user-managed records (accounts, sources, categories).
class ManagedList extends StatelessWidget {
  const ManagedList({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onReorder,
    required this.onAction,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.addLabel,
    required this.onAdd,
  });

  final List<ManagedItem> items;
  final void Function(String id) onOpen;

  /// Called with the active (non-archived) ids in their new order.
  final void Function(List<String> ids) onReorder;
  final void Function(String id, ManagedAction action) onAction;
  final String emptyTitle;
  final String emptyMessage;
  final String addLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final active = items.where((i) => !i.archived).toList();
    final archived = items.where((i) => i.archived).toList();
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: addLabel,
        onAction: onAdd,
      );
    }
    return ReorderableListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final ids = active.map((e) => e.id).toList();
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        onReorder(ids);
      },
      footer: archived.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Archived'),
                for (final item in archived) _tile(context, item, null),
              ],
            ),
      children: [
        for (var i = 0; i < active.length; i++)
          _tile(context, active[i], i, key: ValueKey(active[i].id)),
      ],
    );
  }

  Widget _tile(BuildContext context, ManagedItem item, int? index, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onTap: () => onOpen(item.id),
        child: Row(
          children: [
            IconBox(iconKey: item.iconKey, color: item.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (item.badge != null) ...[
                        const SizedBox(width: 8),
                        StatusChip(item.badge!, color: scheme.outline),
                      ],
                    ],
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            ?item.trailing,
            PopupMenuButton<ManagedAction>(
              onSelected: (a) => onAction(item.id, a),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: ManagedAction.edit,
                  child: Text('Edit'),
                ),
                if (!item.locked)
                  PopupMenuItem(
                    value: item.archived
                        ? ManagedAction.unarchive
                        : ManagedAction.archive,
                    child: Text(item.archived ? 'Unarchive' : 'Archive'),
                  ),
                if (!item.locked)
                  const PopupMenuItem(
                    value: ManagedAction.delete,
                    child: Text('Delete'),
                  ),
              ],
            ),
            if (index != null)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.drag_handle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
