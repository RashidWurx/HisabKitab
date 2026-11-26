import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/widgets.dart';

/// Types the Add / edit form can change.
const _editable = {
  TransactionType.expense,
  TransactionType.income,
  TransactionType.transfer,
};

/// Opens the screen that manages [t]: its due, its 3rd party record, or the
/// transaction form.
Future<void> openTransaction(
  BuildContext context,
  WidgetRef ref,
  Transaction t,
) async {
  if (t.dueId != null) {
    context.push('/dues/${t.dueId}');
  } else if (t.type == TransactionType.passIn ||
      t.type == TransactionType.passOut) {
    final id = await ref
        .read(passRepositoryProvider)
        .passIdForTransaction(t.id);
    if (id != null && context.mounted) context.push('/third-party/$id');
  } else if (_editable.contains(t.type)) {
    context.push('/transaction/${t.id}/edit');
  } else {
    showMessage(context, 'Lend, borrow and repayments are managed from Dues.');
  }
}
