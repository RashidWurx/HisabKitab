import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/widgets.dart';

/// The "+" menu.
Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      void go(String path) {
        Navigator.pop(ctx);
        context.push(path);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quick add',
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _tile(
                    ctx,
                    Icons.south_west,
                    'Expense',
                    () => go('/transaction/new/expense'),
                  ),
                  _tile(
                    ctx,
                    Icons.north_east,
                    'Income',
                    () => go('/transaction/new/income'),
                  ),
                  _tile(
                    ctx,
                    Icons.swap_horiz,
                    'Transfer',
                    () => go('/transaction/new/transfer'),
                  ),
                  _tile(ctx, Icons.volunteer_activism_outlined, 'Lend', () => go('/dues/new/lent')),
                  _tile(ctx, Icons.handshake_outlined, 'Borrow', () => go('/dues/new/borrowed')),
                  _tile(
                    ctx,
                    Icons.event_available_outlined,
                    'Expected\ncash in',
                    () => go('/dues/new/expected'),
                  ),
                  _tile(
                    ctx,
                    Icons.schedule_send_outlined,
                    'Plan a\npayment',
                    () => go('/reminders/new?kind=payment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _tile(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onTap,
) {
  final enabled = onTap != null;
  return Opacity(
    opacity: enabled ? 1 : 0.45,
    child: AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap ??
          () => showMessage(context, 'Coming with Dues in a later phase.'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
