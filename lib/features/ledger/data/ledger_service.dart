import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../transactions/domain/transaction_models.dart';

/// A period. `null` start/end means open-ended. [end] is exclusive.
class DateRange {
  const DateRange({this.start, this.end});

  final DateTime? start;
  final DateTime? end;

  static const all = DateRange();

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class CategorySpend {
  const CategorySpend(this.categoryId, this.amount);
  final String? categoryId;
  final int amount;
}

class AccountPeriodStats {
  const AccountPeriodStats({required this.moneyIn, required this.moneyOut});

  /// Income only (transfers and lend/borrow are not income).
  final int moneyIn;

  /// Expenses only (transfers and lend/borrow are not expenses).
  final int moneyOut;

  int get net => moneyIn - moneyOut;

  /// net / money in, as a percentage. Null when there is no income.
  double? get marginPercent => moneyIn == 0 ? null : net * 100 / moneyIn;
}

class SourcePeriodStats {
  const SourcePeriodStats({required this.received, required this.spent});
  final int received;
  final int spent;
}

/// The ONE place balances and totals are calculated. Never do money maths in
/// widgets. Balances are never stored; they come from transactions, their
/// allocations and the opening balances.
class LedgerService {
  LedgerService(this._db);

  final AppDatabase _db;

  Set<TableInfo> get _balanceTables => {
    _db.transactions,
    _db.transactionAllocations,
    _db.accounts,
    _db.accountOpeningAllocations,
  };

  // Signed movement of source money per account. Enum values are stored as
  // their Dart names (camelCase).
  static const _sourceBalanceSql = '''
SELECT account_id, source_id, SUM(amt) AS bal FROM (
  SELECT t.account_id AS account_id, a.source_id AS source_id,
         CASE WHEN t.type IN ('income','borrowIn','repayIn')
              THEN a.amount ELSE -a.amount END AS amt
    FROM transaction_allocations a
    JOIN transactions t ON t.id = a.transaction_id
  UNION ALL
  SELECT t.to_account_id, a.source_id, a.amount
    FROM transaction_allocations a
    JOIN transactions t ON t.id = a.transaction_id
   WHERE t.type = 'transfer' AND t.to_account_id IS NOT NULL
  UNION ALL
  SELECT account_id, source_id, amount FROM account_opening_allocations
  UNION ALL
  SELECT ac.id, '$otherMoneySourceId',
         ac.opening_balance - COALESCE((
           SELECT SUM(o.amount) FROM account_opening_allocations o
            WHERE o.account_id = ac.id), 0)
    FROM accounts ac
) GROUP BY account_id, source_id
''';

  Map<AccountSource, int> _mapSourceRows(List<QueryRow> rows) => {
    for (final r in rows)
      if (r.read<int>('bal') != 0)
        AccountSource(
          r.read<String>('account_id'),
          r.read<String>('source_id'),
        ): r.read<int>(
          'bal',
        ),
  };

  /// Money of each source sitting in each account. Zero balances are omitted.
  Stream<Map<AccountSource, int>> watchSourceBalances() => _db
      .customSelect(_sourceBalanceSql, readsFrom: _balanceTables)
      .watch()
      .map(_mapSourceRows);

  Future<Map<AccountSource, int>> sourceBalances() async => _mapSourceRows(
    await _db.customSelect(_sourceBalanceSql, readsFrom: _balanceTables).get(),
  );

  /// Account balance = sum of its source balances.
  static Map<String, int> accountTotals(Map<AccountSource, int> balances) {
    final out = <String, int>{};
    balances.forEach((k, v) => out[k.accountId] = (out[k.accountId] ?? 0) + v);
    return out;
  }

  /// Balance of each source across all accounts.
  static Map<String, int> sourceTotals(Map<AccountSource, int> balances) {
    final out = <String, int>{};
    balances.forEach((k, v) => out[k.sourceId] = (out[k.sourceId] ?? 0) + v);
    return out;
  }

  /// Sources' money inside one account.
  static Map<String, int> sourcesInAccount(
    Map<AccountSource, int> balances,
    String accountId,
  ) {
    final out = <String, int>{};
    balances.forEach((k, v) {
      if (k.accountId == accountId) out[k.sourceId] = v;
    });
    return out;
  }

  /// Headline numbers: total across accounts flagged "include in total"
  /// (archived accounts too, since their money still exists), and how much of
  /// that total is in savings accounts.
  static ({int total, int savings}) headlineTotals(
    List<Account> accounts,
    Map<String, int> accountBalances,
  ) {
    var total = 0;
    var savings = 0;
    for (final a in accounts) {
      if (!a.includeInTotal) continue;
      final b = accountBalances[a.id] ?? 0;
      total += b;
      if (a.type == AccountType.savings) savings += b;
    }
    return (total: total, savings: savings);
  }

  /// The money that is really yours: what the accounts hold minus what is
  /// still owed on borrowed money. Negative when you owe more than you have.
  static int netBalance({required int inAccounts, required int borrowedOwed}) =>
      inAccounts - borrowedOwed;

  /// Net cash movement of a day's transactions: money in minus money out.
  /// Transfers are neutral.
  static int dayNet(Iterable<Transaction> transactions) {
    var net = 0;
    for (final t in transactions) {
      if (moneyInTypes.contains(t.type)) {
        net += t.amount;
      } else if (moneyOutTypes.contains(t.type)) {
        net -= t.amount;
      }
    }
    return net;
  }

  Stream<Map<String, int>> watchAccountBalances() =>
      watchSourceBalances().map(accountTotals);

  /// Independent check: account balances worked out from transaction amounts
  /// only (no allocations). Must always equal the sum of source balances.
  Future<Map<String, int>> accountBalancesFromTransactions() async {
    final rows = await _db.customSelect('''
SELECT ac.id AS id,
       ac.opening_balance
       + COALESCE((SELECT SUM(CASE WHEN t.type IN ('income','borrowIn','repayIn') THEN t.amount ELSE -t.amount END)
                     FROM transactions t WHERE t.account_id = ac.id), 0)
       + COALESCE((SELECT SUM(t.amount) FROM transactions t
                    WHERE t.to_account_id = ac.id AND t.type = 'transfer'), 0) AS bal
  FROM accounts ac
''', readsFrom: _balanceTables).get();
    return {for (final r in rows) r.read<String>('id'): r.read<int>('bal')};
  }

  // ---- Period stats -------------------------------------------------------

  (String, List<Variable>) _rangeClause(DateRange r, [String col = 't.date']) {
    final parts = <String>[];
    final vars = <Variable>[];
    if (r.start != null) {
      parts.add('$col >= ?');
      vars.add(Variable.withDateTime(r.start!));
    }
    if (r.end != null) {
      parts.add('$col < ?');
      vars.add(Variable.withDateTime(r.end!));
    }
    return (parts.isEmpty ? '' : ' AND ${parts.join(' AND ')}', vars);
  }

  /// Income / expense totals across all accounts for a period.
  Stream<AccountPeriodStats> watchPeriodTotals(
    DateRange range, {
    String? accountId,
  }) {
    final (clause, vars) = _rangeClause(range);
    final acct = accountId == null ? '' : ' AND t.account_id = ?';
    return _db
        .customSelect(
          '''
SELECT
  COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount END), 0) AS money_in,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount END), 0) AS money_out
  FROM transactions t WHERE 1 = 1$clause$acct
''',
          variables: [...vars, if (accountId != null) Variable(accountId)],
          readsFrom: {_db.transactions},
        )
        .watchSingle()
        .map(
          (r) => AccountPeriodStats(
            moneyIn: r.read<int>('money_in'),
            moneyOut: r.read<int>('money_out'),
          ),
        );
  }

  /// Expense totals per category, biggest first. Optionally limited to one
  /// account, or to one source (then the allocation amounts are used).
  Stream<List<CategorySpend>> watchSpendingByCategory(
    DateRange range, {
    String? accountId,
    String? sourceId,
  }) {
    final (clause, vars) = _rangeClause(range);
    final acct = accountId == null ? '' : ' AND t.account_id = ?';
    final bySource = sourceId != null;
    final sql =
        '''
SELECT t.category_id AS category_id, SUM(${bySource ? 'a.amount' : 't.amount'}) AS total
  FROM transactions t
  ${bySource ? 'JOIN transaction_allocations a ON a.transaction_id = t.id AND a.source_id = ?' : ''}
 WHERE t.type = 'expense'$clause$acct
 GROUP BY t.category_id
 ORDER BY total DESC
''';
    return _db
        .customSelect(
          sql,
          variables: [
            if (bySource) Variable(sourceId),
            ...vars,
            if (accountId != null) Variable(accountId),
          ],
          readsFrom: {_db.transactions, _db.transactionAllocations},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              CategorySpend(
                r.readNullable<String>('category_id'),
                r.read<int>('total'),
              ),
          ],
        );
  }

  /// Money received (income) and spent (expenses) tagged to a source.
  Stream<SourcePeriodStats> watchSourceStats(
    String sourceId,
    DateRange range,
  ) {
    final (clause, vars) = _rangeClause(range);
    return _db
        .customSelect(
          '''
SELECT
  COALESCE(SUM(CASE WHEN t.type = 'income' THEN a.amount END), 0) AS received,
  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN a.amount END), 0) AS spent
  FROM transaction_allocations a
  JOIN transactions t ON t.id = a.transaction_id
 WHERE a.source_id = ?$clause
''',
          variables: [Variable(sourceId), ...vars],
          readsFrom: {_db.transactions, _db.transactionAllocations},
        )
        .watchSingle()
        .map(
          (r) => SourcePeriodStats(
            received: r.read<int>('received'),
            spent: r.read<int>('spent'),
          ),
        );
  }
}
