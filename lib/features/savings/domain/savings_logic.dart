/// Progress towards a savings goal as 0..1 (more than the goal counts as 1).
double savingsProgress({required int balance, required int? goal}) {
  if (goal == null || goal <= 0) return 0;
  if (balance <= 0) return 0;
  final p = balance / goal;
  return p > 1 ? 1 : p;
}

/// How much is still needed to reach the goal (0 when reached or no goal).
int savingsRemaining({required int balance, required int? goal}) {
  if (goal == null || goal <= 0) return 0;
  final left = goal - balance;
  return left < 0 ? 0 : left;
}
