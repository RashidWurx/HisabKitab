import '../../../core/database/enums.dart';

/// One source's share of a transaction (paisa).
class AllocationInput {
  const AllocationInput(this.sourceId, this.amount);

  final String sourceId;
  final int amount;

  @override
  bool operator ==(Object other) =>
      other is AllocationInput &&
      other.sourceId == sourceId &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(sourceId, amount);

  @override
  String toString() => 'Alloc($sourceId, $amount)';
}

/// Key for "money of source S sitting in account A".
class AccountSource {
  const AccountSource(this.accountId, this.sourceId);

  final String accountId;
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is AccountSource &&
      other.accountId == accountId &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(accountId, sourceId);

  @override
  String toString() => 'AS($accountId, $sourceId)';
}

/// Everything needed to save (or restore) a transaction and its allocations.
class TransactionInput {
  const TransactionInput({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.personId,
    this.dueId,
    this.subscriptionId,
    required this.date,
    this.note,
    required this.allocations,
    this.createdAt,
  });

  final String? id;
  final TransactionType type;
  final int amount;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String? personId;
  final String? dueId;
  final String? subscriptionId;
  final DateTime date;
  final String? note;
  final List<AllocationInput> allocations;
  final DateTime? createdAt;

  TransactionInput copyWith({
    int? amount,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    DateTime? date,
    String? note,
    List<AllocationInput>? allocations,
  }) => TransactionInput(
    id: id,
    type: type,
    amount: amount ?? this.amount,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId ?? this.toAccountId,
    categoryId: categoryId ?? this.categoryId,
    personId: personId,
    dueId: dueId,
    subscriptionId: subscriptionId,
    date: date ?? this.date,
    note: note ?? this.note,
    allocations: allocations ?? this.allocations,
    createdAt: createdAt,
  );
}

/// Types whose money enters `accountId`.
const moneyInTypes = {
  TransactionType.income,
  TransactionType.borrowIn,
  TransactionType.repayIn,
};

/// Types whose money leaves `accountId`.
const moneyOutTypes = {
  TransactionType.expense,
  TransactionType.lendOut,
  TransactionType.repayOut,
};

/// How a transaction changes each (account, source) balance. The pure-Dart
/// twin of the SQL in `LedgerService`; used for previews and tests.
Map<AccountSource, int> transactionDeltas(TransactionInput t) {
  final out = <AccountSource, int>{};
  void add(String account, String source, int amount) {
    final key = AccountSource(account, source);
    out[key] = (out[key] ?? 0) + amount;
  }

  for (final a in t.allocations) {
    if (moneyInTypes.contains(t.type)) {
      add(t.accountId, a.sourceId, a.amount);
    } else if (moneyOutTypes.contains(t.type)) {
      add(t.accountId, a.sourceId, -a.amount);
    } else if (t.type == TransactionType.transfer) {
      add(t.accountId, a.sourceId, -a.amount);
      if (t.toAccountId != null) add(t.toAccountId!, a.sourceId, a.amount);
    }
  }
  return out;
}
