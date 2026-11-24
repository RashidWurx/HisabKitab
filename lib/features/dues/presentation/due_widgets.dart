import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/theme/app_theme.dart';
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
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: 15, color: c),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
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
    final person = people[d.personId];
    final source = sources[d.sourceId];
    final sub = person?.name ?? source?.name ?? 'Expected cash in';
    final overdue = view.status == DueStatus.overdue;
    final closed =
        view.status == DueStatus.settled || view.status == DueStatus.cancelled;
    final amountColor = closed
        ? scheme.onSurfaceVariant
        : overdue
        ? colors.negative
        : (view.isReceivable ? colors.positive : colors.negative);
    final accent = statusColor(context, view.status);
    final progress = view.total == 0 ? 0.0 : view.paid / view.total;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        person != null
                            ? InitialsAvatar(person.name, size: 42)
                            : IconBox(
                                iconKey: source?.iconKey ?? 'work',
                                color: source == null
                                    ? null
                                    : Color(source.colorValue),
                                size: 42,
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                sub,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        DueStatusChip(view.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                view.status == DueStatus.settled
                                    ? 'Settled'
                                    : 'Remaining',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                Money.format(
                                  view.status == DueStatus.settled
                                      ? view.total
                                      : view.remaining,
                                ),
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: amountColor,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'of ${Money.format(view.total)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Due ${formatDateShort(d.currentDueDate)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (view.paid > 0 && !closed) ...[
                      const SizedBox(height: 10),
                      SoftProgress(value: progress, color: colors.partial, height: 6),
                    ],
                    if ((view.lateDays > 0 &&
                            view.status != DueStatus.cancelled) ||
                        view.extensionCount > 0 ||
                        onQuickReceive != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (view.lateDays > 0 &&
                                    view.status != DueStatus.cancelled)
                                  _badge(
                                    'Late by ${view.lateDays} days',
                                    colors.negative,
                                  ),
                                if (view.extensionCount > 0)
                                  _badge(
                                    'Extended ${view.extensionCount}×',
                                    colors.partial,
                                  ),
                              ],
                            ),
                          ),
                          if (onQuickReceive != null)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onPressed: onQuickReceive,
                              child: const Text('Received'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
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
