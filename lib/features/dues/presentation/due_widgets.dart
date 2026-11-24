import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/money.dart';
import '../domain/due_models.dart';

String statusLabel(DueStatus s) => switch (s) {
  DueStatus.pending => 'Pending',
  DueStatus.partial => 'Partial',
  DueStatus.overdue => 'Overdue',
  DueStatus.settled => 'Settled',
  DueStatus.cancelled => 'Cancelled',
};

/// Pending amber, partial blue, overdue red, settled green.
Color statusColor(BuildContext context, DueStatus s) {
  final c = context.appColors;
  return switch (s) {
    DueStatus.pending => c.pending,
    DueStatus.partial => c.partial,
    DueStatus.overdue => c.overdue,
    DueStatus.settled => c.settled,
    DueStatus.cancelled => Theme.of(context).colorScheme.outline,
  };
}

IconData statusIcon(DueStatus s) => switch (s) {
  DueStatus.pending => Icons.schedule,
  DueStatus.partial => Icons.timelapse,
  DueStatus.overdue => Icons.error_outline,
  DueStatus.settled => Icons.check_circle_outline,
  DueStatus.cancelled => Icons.block,
};

class DueStatusChip extends StatelessWidget {
  const DueStatusChip(this.status, {super.key});

  final DueStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: 16, color: c),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

String formatDate(DateTime d) => DateFormat('d MMM y').format(d);
String formatDateShort(DateTime d) => DateFormat('d MMM').format(d);
String formatDateTime(DateTime d) => DateFormat('d MMM y, h:mm a').format(d);

/// A due in a list (Dues screen, person page, source page).
class DueTile extends StatelessWidget {
  const DueTile({
    super.key,
    required this.view,
    required this.people,
    required this.sources,
    this.onTap,
    this.onQuickReceive,
  });

  final DueView view;
  final Map<String, PeopleData> people;
  final Map<String, IncomeSource> sources;
  final VoidCallback? onTap;

  /// Shows a one-tap "Received" button (payday / expected income dues).
  final VoidCallback? onQuickReceive;

  @override
  Widget build(BuildContext context) {
    final d = view.due;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final who = people[d.personId]?.name;
    final sub = who ?? sources[d.sourceId]?.name ?? 'Expected cash in';
    final overdue = view.status == DueStatus.overdue;
    final amountColor = view.status == DueStatus.settled ||
            view.status == DueStatus.cancelled
        ? scheme.onSurfaceVariant
        : overdue
        ? colors.negative
        : (view.isReceivable ? colors.positive : colors.negative);
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DueStatusChip(view.status),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: Money.format(
                    view.status == DueStatus.settled ? view.total : view.remaining,
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
                TextSpan(
                  text: view.status == DueStatus.settled
                      ? ' settled'
                      : ' remaining of ${Money.format(view.total)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Due: ${formatDateShort(d.currentDueDate)}'),
                    if (view.lateDays > 0 && view.status != DueStatus.cancelled)
                      _badge(context, 'Late by ${view.lateDays} days', colors.negative),
                    if (view.extensionCount > 0)
                      _badge(context, 'Extended ${view.extensionCount}×', colors.partial),
                  ],
                ),
              ),
              if (onQuickReceive != null)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: onQuickReceive,
                  child: const Text('Received'),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

/// Sorts dues for lists: overdue first, then by current due date.
List<DueView> sortDues(Iterable<DueView> views) {
  final list = views.toList();
  int rank(DueStatus s) => s == DueStatus.overdue ? 0 : 1;
  list.sort((a, b) {
    final r = rank(a.status).compareTo(rank(b.status));
    if (r != 0) return r;
    return a.due.currentDueDate.compareTo(b.due.currentDueDate);
  });
  return list;
}
