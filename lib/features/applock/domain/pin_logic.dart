import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// How long the app may stay in the background before it locks again.
enum LockTimeout {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes');

  const LockTimeout(this.duration, this.label);
  final Duration duration;
  final String label;
}

/// A PIN is 4 to 6 digits.
bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

Uint8List generateSalt([int length = 16]) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// PBKDF2-HMAC-SHA256. The PIN is never stored: only this hash and a random
/// salt (in secure storage).
Uint8List hashPin(String pin, Uint8List salt, {int iterations = 10000}) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  // One 32-byte block is enough (derived key length = SHA-256 output).
  final block = Uint8List(salt.length + 4)
    ..setRange(0, salt.length, salt)
    ..[salt.length + 3] = 1;
  var u = Uint8List.fromList(hmac.convert(block).bytes);
  final result = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

/// Compares without stopping at the first difference.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// How many seconds the PIN pad stays locked after [failedAttempts] wrong
/// tries in a row. The first 4 are free, then it gets slower.
int lockoutSeconds(int failedAttempts) {
  if (failedAttempts < 5) return 0;
  const steps = [30, 60, 300, 900, 3600];
  final index = failedAttempts - 5;
  return steps[index >= steps.length ? steps.length - 1 : index];
}

/// Whether the app should lock when it returns to the foreground.
bool shouldLockOnResume({
  required bool lockEnabled,
  required DateTime? backgroundedAt,
  required DateTime now,
  required LockTimeout timeout,
}) {
  if (!lockEnabled) return false;
  if (backgroundedAt == null) return true; // unknown: be safe
  return now.difference(backgroundedAt) >= timeout.duration;
}
