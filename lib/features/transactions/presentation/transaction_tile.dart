import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/ui/icon_registry.dart';
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
        iconKey = 'swap';
      case TransactionType.lendOut:
        title = 'Lent';
        subtitle = account?.name ?? '';
        iconKey = 'people';
      case TransactionType.borrowIn:
        title = 'Borrowed';
        subtitle = account?.name ?? '';
        iconKey = 'people';
      case TransactionType.repayIn:
        title = 'Repayment received';
        subtitle = account?.name ?? '';
        iconKey = 'people';
      case TransactionType.repayOut:
        title = 'Repayment paid';
        subtitle = account?.name ?? '';
        iconKey = 'people';
      default:
        title = category?.name ?? (t.type == TransactionType.income ? 'Income' : 'Expense');
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            t.type == TransactionType.transfer
                ? const SizedBox(
                    width: 32,
                    child: Icon(Icons.swap_horiz, size: 28),
                  )
                : SizedBox(
                    width: 32,
                    child: Icon(iconFor(iconKey), size: 28, color: color),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            MoneyText(
              signed,
              neutral: t.type == TransactionType.transfer,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
