import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/ui/widgets.dart';
import '../domain/transaction_models.dart';

/// One row in a transaction list (Activity, account details, ...).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.accounts,
    required this.categories,
    this.onTap,
  });

  final Transaction transaction;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final scheme = Theme.of(context).colorScheme;
    final account = accounts[t.accountId];
    final category = categories[t.categoryId];
    final toAccount = accounts[t.toAccountId];
    String title;
    String subtitle;
    String iconKey;
    Color? color;
    switch (t.type) {
      case TransactionType.transfer:
        title = 'Transfer';
        subtitle = '${account?.name ?? '?'} → ${toAccount?.name ?? '?'}';
        iconKey = 'bank';
        color = const Color(0xFF2A4E76);
      case TransactionType.lendOut:
        title = 'Lent';
        subtitle = account?.name ?? '';
        iconKey = 'people';
        color = const Color(0xFF9C27B0);
      case TransactionType.borrowIn:
        title = 'Borrowed';
        subtitle = account?.name ?? '';
        iconKey = 'people';
        color = const Color(0xFF9C27B0);
      case TransactionType.repayIn:
        title = 'Repayment received';
        subtitle = account?.name ?? '';
        iconKey = 'people';
        color = const Color(0xFF9C27B0);
      case TransactionType.repayOut:
        title = 'Repayment paid';
        subtitle = account?.name ?? '';
        iconKey = 'people';
        color = const Color(0xFF9C27B0);
      case TransactionType.passIn:
      case TransactionType.passOut:
        title = t.type == TransactionType.passIn
            ? '3rd party received'
            : '3rd party paid';
        subtitle = account?.name ?? '';
        iconKey = 'people';
        color = const Color(0xFF00796B);
      default:
        title =
            category?.name ??
            (t.type == TransactionType.income ? 'Income' : 'Expense');
        subtitle = account?.name ?? '';
        iconKey = category?.iconKey ?? 'category';
        color = category == null ? null : Color(category.colorValue);
    }
    if (t.note != null && t.note!.isNotEmpty) subtitle = '$subtitle · ${t.note}';

    final signed = moneyInTypes.contains(t.type)
        ? t.amount
        : moneyOutTypes.contains(t.type)
        ? -t.amount
        : t.amount; // transfer: neutral
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            t.type == TransactionType.transfer
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color!.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.swap_horiz_rounded, color: color),
                  )
                : IconBox(iconKey: iconKey, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(
              signed,
              neutral: t.type == TransactionType.transfer,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
