import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../domain/due_models.dart';
import 'due_repository.dart';

/// Creates the NEXT payday's "expected income" due for every active source
/// with a pay schedule (rolling: only one period ahead, never months or
/// years in advance). Safe to call any number of times: each due has a
/// unique period key (`sourceId:yyyy-MM-dd`).
class PaydayService {
  PaydayService(this._db) : _dues = DueRepository(_db);

  final AppDatabase _db;
  final DueRepository _dues;

  Future<int> ensureNextPaydays({DateTime? now}) async {
    final today = dateOnly(now ?? DateTime.now());
    final sources =
        await (_db.select(_db.incomeSources)..where(
              (s) =>
                  s.isArchived.equals(false) &
                  s.isBuiltIn.equals(false) &
                  s.status.equals(ActiveStatus.active.name) &
                  s.linkedAccountId.isNotNull(),
            ))
            .get();
    var created = 0;
    for (final s in sources) {
      final amount = s.expectedAmount;
      if (amount == null || amount <= 0) continue; // nothing to expect yet
      final next = nextPayday(
        type: s.payScheduleType,
        payDay: s.payDay,
        intervalDays: s.payIntervalDays,
        anchor: s.payAnchorDate,
        from: today,
      );
      if (next == null) continue;
      final key = '${s.id}:${DateFormat('yyyy-MM-dd').format(next)}';
      final exists = await (_db.select(
        _db.dues,
      )..where((d) => d.periodKey.equals(key))).getSingleOrNull();
      if (exists != null) continue;
      await _dues.create(
        DueDraft(
          title: _title(s, next),
          kind: DueKind.expectedIncome,
          sourceId: s.id,
          totalAmount: amount,
          accountId: s.linkedAccountId!,
          dueDate: next,
          periodKey: key,
        ),
      );
      created++;
    }
    return created;
  }

  static String _title(IncomeSource s, DateTime payday) =>
      s.payScheduleType == PayScheduleType.monthly
      ? '${s.name} salary, ${DateFormat('MMM y').format(payday)}'
      : '${s.name} pay, ${DateFormat('d MMM y').format(payday)}';
}
