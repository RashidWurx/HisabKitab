import 'transaction_models.dart';

/// Picks which source's money an expense uses, in this order:
/// 1. the category's default source, if it has money in the account
/// 2. the account's default spending source
/// 3. the source with the most money left in the account
/// Falls back to [fallbackSourceId] ("Other money") when nothing fits.
String autoPickSource({
  required Map<String, int> balancesInAccount,
  String? categoryDefaultSourceId,
  String? accountDefaultSourceId,
  required String fallbackSourceId,
}) {
  if (categoryDefaultSourceId != null &&
      (balancesInAccount[categoryDefaultSourceId] ?? 0) > 0) {
    return categoryDefaultSourceId;
  }
  if (accountDefaultSourceId != null) return accountDefaultSourceId;
  String? best;
  var bestBalance = 0;
  balancesInAccount.forEach((id, balance) {
    if (balance > bestBalance) {
      best = id;
      bestBalance = balance;
    }
  });
  return best ?? fallbackSourceId;
}

/// How much [amount] exceeds what [sourceId] has in the account (0 if enough).
int shortfall({required int sourceBalance, required int amount}) {
  final available = sourceBalance < 0 ? 0 : sourceBalance;
  return amount > available ? amount - available : 0;
}

/// "Split with another source": [primary] gives what it has, the rest is
/// filled from other sources (largest balance first). If the account's money
/// is still not enough, the leftover stays on [primary] (it goes negative).
List<AllocationInput> splitWithOtherSources({
  required String primary,
  required int amount,
  required Map<String, int> balancesInAccount,
}) {
  final primaryBalance = balancesInAccount[primary] ?? 0;
  final fromPrimary = primaryBalance <= 0
      ? 0
      : (primaryBalance < amount ? primaryBalance : amount);
  final result = <AllocationInput>[];
  var remaining = amount - fromPrimary;

  final others =
      balancesInAccount.entries
          .where((e) => e.key != primary && e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final extra = <AllocationInput>[];
  for (final e in others) {
    if (remaining <= 0) break;
    final take = e.value < remaining ? e.value : remaining;
    extra.add(AllocationInput(e.key, take));
    remaining -= take;
  }
  final primaryTotal = fromPrimary + remaining; // leftover goes negative here
  if (primaryTotal > 0) result.add(AllocationInput(primary, primaryTotal));
  result.addAll(extra);
  return result;
}

/// True when allocations are all positive and add up exactly to [amount].
bool allocationsValid(List<AllocationInput> allocations, int amount) {
  if (allocations.isEmpty) return false;
  var sum = 0;
  for (final a in allocations) {
    if (a.amount <= 0) return false;
    sum += a.amount;
  }
  return sum == amount;
}
