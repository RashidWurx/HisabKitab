import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../ledger/data/ledger_service.dart';

class DueSummary {
  const DueSummary({
    required this.toReceive,
    required this.toPay,
    required this.overdueCount,
  });

  /// Remaining of all expected-income and lent dues.
  final int toReceive;

  /// Remaining of all borrowed dues.
  final int toPay;

  /// How many of the "to receive" dues are past their current due date.
  final int overdueCount;

  static const empty = DueSummary(toReceive: 0, toPay: 0, overdueCount: 0);
}

class SourceDashRow {
  const SourceDashRow({
    required this.sourceId,
    required this.received,
    required this.spent,
    required this.expected,
    this.expectedAccountId,
  });

  final String sourceId;

  /// Income received / expenses spent from this source in the period.
  final int received;
  final int spent;

  /// Still expected (open expected-income dues) for this source.
  final int expected;
  final String? expectedAccountId;
}

class AccountDashRow {
  const AccountDashRow({
    required this.accountId,
    required this.moneyIn,
    required this.moneyOut,
    required this.expected,
  });

  final String accountId;
  final int moneyIn;
  final int moneyOut;

  /// Still expected to arrive in this account (expected-income and lent dues).
  final int expected;
}

enum UpcomingKind { due, subscription, reminder, payment }

class UpcomingItem {
  const UpcomingItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.date,
    this.amount,
    this.isMoneyIn = false,
  });

  final UpcomingKind kind;
  final String id;
  final String title;
  final DateTime date;

  /// Positive paisa, if the item has an amount.
  final int? amount;

  /// True for money coming in (expected income, lent), false for money going out.
  final bool isMoneyIn;
}

/// Dashboard numbers. Like [LedgerService], all money maths lives here.
class DashboardService {
  DashboardService(this._db);

  final AppDatabase _db;

  /// Remaining amount of a due: total - written off - payments received/made.
  /// (lend_out / borrow_in create the due, so they are not payments.)
  static const _remaining = '''
(d.total_amount - d.written_off_amount - COALESCE((
   SELECT SUM(t.amount) FROM transactions t
    WHERE t.due_id = d.id AND t.type IN ('income','repayIn','repayOut')), 0))
''';

  /// Keeps the [n] biggest categories and folds the rest into one
  /// "other categories" slice (id [otherCategoriesId]).
  static List<CategorySpend> topWithOther(List<CategorySpend> spend, int n) {
    if (spend.length <= n) return spend;
    final sorted = [...spend]..sort((a, b) => b.amount.compareTo(a.amount));
    final rest = sorted.skip(n).fold<int>(0, (s, e) => s + e.amount);
    return [...sorted.take(n), CategorySpend(otherCategoriesId, rest)];
  }

  static const otherCategoriesId = '_other_categories';

  Set<TableInfo> get _dueTables => {_db.dues, _db.transactions};

  Stream<DueSummary> watchDueSummary({DateTime? now}) {
    final today = DateUtils0.startOfDay(now ?? DateTime.now());
    return _db
        .customSelect(
          '''
SELECT
  COALESCE(SUM(CASE WHEN kind IN ('expectedIncome','lent') THEN rem END), 0) AS to_receive,
  COALESCE(SUM(CASE WHEN kind = 'borrowed' THEN rem END), 0) AS to_pay,
  COALESCE(SUM(CASE WHEN kind IN ('expectedIncome','lent')
                     AND current_due_date < ? THEN 1 END), 0) AS overdue
  FROM (SELECT d.kind AS kind, d.current_due_date AS current_due_date,
               $_remaining AS rem
          FROM dues d WHERE d.cancelled_at IS NULL)
 WHERE rem > 0
''',
          variables: [Variable.withDateTime(today)],
          readsFrom: _dueTables,
        )
        .watchSingle()
        .map(
          (r) => DueSummary(
            toReceive: r.read<int>('to_receive'),
            toPay: r.read<int>('to_pay'),
            overdueCount: r.read<int>('overdue'),
          ),
        );
  }

  /// Received / spent per source for a period, plus what is still expected.
  Stream<Map<String, SourceDashRow>> watchSourceRows(DateRange range) {
    final (clause, vars) = _range(range);
    final flows = _db
        .customSelect(
          '''
SELECT a.source_id AS source_id,
  COALESCE(SUM(CASE WHEN t.type = 'income' THEN a.amount END), 0) AS received,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN a.amount END), 0) AS spent
  FROM transaction_allocations a
  JOIN transactions t ON t.id = a.transaction_id
 WHERE 1 = 1$clause
 GROUP BY a.source_id
''',
          variables: vars,
          readsFrom: {_db.transactions, _db.transactionAllocations},
        )
        .watch();
    final expected = _db
        .customSelect(
          '''
SELECT source_id, account_id, SUM(rem) AS expected FROM (
  SELECT d.source_id AS source_id, d.account_id AS account_id,
         $_remaining AS rem
    FROM dues d
   WHERE d.cancelled_at IS NULL AND d.kind = 'expectedIncome'
     AND d.source_id IS NOT NULL)
 WHERE rem > 0 GROUP BY source_id, account_id
''',
          readsFrom: _dueTables,
        )
        .watch();
    return _combine(flows, expected, (f, e) {
      final out = <String, SourceDashRow>{};
      for (final r in f) {
        final id = r.read<String>('source_id');
        out[id] = SourceDashRow(
          sourceId: id,
          received: r.read<int>('received'),
          spent: r.read<int>('spent'),
          expected: 0,
        );
      }
      for (final r in e) {
        final id = r.read<String>('source_id');
        final prev = out[id];
        out[id] = SourceDashRow(
          sourceId: id,
          received: prev?.received ?? 0,
          spent: prev?.spent ?? 0,
          expected: (prev?.expected ?? 0) + r.read<int>('expected'),
          expectedAccountId: r.readNullable<String>('account_id'),
        );
      }
      return out;
    });
  }

  /// Money in / out per account for a period, plus expected incoming money.
  Stream<Map<String, AccountDashRow>> watchAccountRows(DateRange range) {
    final (clause, vars) = _range(range);
    final flows = _db
        .customSelect(
          '''
SELECT t.account_id AS account_id,
  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount END), 0) AS money_in,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount END), 0) AS money_out
  FROM transactions t WHERE 1 = 1$clause GROUP BY t.account_id
''',
          variables: vars,
          readsFrom: {_db.transactions},
        )
        .watch();
    final expected = _db
        .customSelect(
          '''
SELECT account_id, SUM(rem) AS expected FROM (
  SELECT d.account_id AS account_id, $_remaining AS rem
    FROM dues d
   WHERE d.cancelled_at IS NULL AND d.kind IN ('expectedIncome','lent'))
 WHERE rem > 0 GROUP BY account_id
''',
          readsFrom: _dueTables,
        )
        .watch();
    return _combine(flows, expected, (f, e) {
      final out = <String, AccountDashRow>{};
      for (final r in f) {
        final id = r.read<String>('account_id');
        out[id] = AccountDashRow(
          accountId: id,
          moneyIn: r.read<int>('money_in'),
          moneyOut: r.read<int>('money_out'),
          expected: 0,
        );
      }
      for (final r in e) {
        final id = r.read<String>('account_id');
        final prev = out[id];
        out[id] = AccountDashRow(
          accountId: id,
          moneyIn: prev?.moneyIn ?? 0,
          moneyOut: prev?.moneyOut ?? 0,
          expected: r.read<int>('expected'),
        );
      }
      return out;
    });
  }

  /// Items due in the next [days] days (including overdue dues, unpaid planned
  /// payments and anything today): open dues, active subscriptions and active
  /// custom reminders.
  Stream<List<UpcomingItem>> watchUpcoming({int days = 7, DateTime? now}) {
    final start = DateUtils0.startOfDay(now ?? DateTime.now());
    final end = start.add(Duration(days: days + 1)); // exclusive
    return _db
        .customSelect(
          '''
SELECT * FROM (
  SELECT 'due' AS kind, d.id AS id, d.title AS title,
         d.current_due_date AS at,
         $_remaining AS amount,
         CASE WHEN d.kind = 'borrowed' THEN 0 ELSE 1 END AS money_in
    FROM dues d
   WHERE d.cancelled_at IS NULL AND d.current_due_date < ?
  UNION ALL
  SELECT 'subscription', s.id, s.name, s.next_due_date, s.amount, 0
    FROM subscriptions s
   WHERE s.status = 'active' AND s.next_due_date < ?
  UNION ALL
  SELECT CASE WHEN r.amount IS NULL THEN 'reminder' ELSE 'payment' END,
         r.id, r.title, r.remind_at, COALESCE(r.amount, 0), 0
    FROM custom_reminders r
   WHERE r.is_active = 1 AND r.remind_at < ?
     AND (r.amount IS NOT NULL OR r.remind_at >= ?)
) WHERE kind <> 'due' OR amount > 0
 ORDER BY at ASC
''',
          variables: [
            Variable.withDateTime(end),
            Variable.withDateTime(end),
            Variable.withDateTime(end),
            Variable.withDateTime(start),
          ],
          readsFrom: {
            _db.dues,
            _db.transactions,
            _db.subscriptions,
            _db.customReminders,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              UpcomingItem(
                kind: switch (r.read<String>('kind')) {
                  'due' => UpcomingKind.due,
                  'subscription' => UpcomingKind.subscription,
                  'payment' => UpcomingKind.payment,
                  _ => UpcomingKind.reminder,
                },
                id: r.read<String>('id'),
                title: r.read<String>('title'),
                date: DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('at') * 1000,
                ),
                amount: r.read<int>('amount') == 0 ? null : r.read<int>('amount'),
                isMoneyIn: r.read<int>('money_in') == 1,
              ),
          ],
        );
  }

  /// Income and expense totals for each of [ranges] (e.g. last 6 months).
  Stream<List<AccountPeriodStats>> watchTotalsPerRange(List<DateRange> ranges) {
    if (ranges.isEmpty) return Stream.value(const []);
    final first = ranges.first.start!;
    final last = ranges.last.end!;
    return _db
        .customSelect(
          '''
SELECT t.type AS type, t.date AS at, t.amount AS amount
  FROM transactions t
 WHERE t.type IN ('income','expense') AND t.date >= ? AND t.date < ?
''',
          variables: [
            Variable.withDateTime(first),
            Variable.withDateTime(last),
          ],
          readsFrom: {_db.transactions},
        )
        .watch()
        .map((rows) {
          final inn = List.filled(ranges.length, 0);
          final out = List.filled(ranges.length, 0);
          for (final r in rows) {
            final at = DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('at') * 1000,
            );
            for (var i = 0; i < ranges.length; i++) {
              if (!at.isBefore(ranges[i].start!) && at.isBefore(ranges[i].end!)) {
                if (r.read<String>('type') == 'income') {
                  inn[i] += r.read<int>('amount');
                } else {
                  out[i] += r.read<int>('amount');
                }
                break;
              }
            }
          }
          return [
            for (var i = 0; i < ranges.length; i++)
              AccountPeriodStats(moneyIn: inn[i], moneyOut: out[i]),
          ];
        });
  }

  (String, List<Variable>) _range(DateRange r) {
    final parts = <String>[];
    final vars = <Variable>[];
    if (r.start != null) {
      parts.add('t.date >= ?');
      vars.add(Variable.withDateTime(r.start!));
    }
    if (r.end != null) {
      parts.add('t.date < ?');
      vars.add(Variable.withDateTime(r.end!));
    }
    return (parts.isEmpty ? '' : ' AND ${parts.join(' AND ')}', vars);
  }

  /// Re-emits whenever either stream emits, once both have a value.
  Stream<R> _combine<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) f,
  ) {
    late StreamController<R> controller;
    StreamSubscription<A>? sa;
    StreamSubscription<B>? sb;
    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;
    void emit() {
      if (hasA && hasB) controller.add(f(lastA as A, lastB as B));
    }

    controller = StreamController<R>(
      onListen: () {
        sa = a.listen((v) {
          lastA = v;
          hasA = true;
          emit();
        }, onError: controller.addError);
        sb = b.listen((v) {
          lastB = v;
          hasB = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Tiny date helper (no Flutter dependency in the data layer).
abstract final class DateUtils0 {
  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}
