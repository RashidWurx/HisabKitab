import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/pin_logic.dart';

/// Minimal key/value interface so tests can use memory instead of the keystore.
abstract class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKv implements SecureKv {
  FlutterSecureKv([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKv implements SecureKv {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class LockConfig {
  const LockConfig({
    this.enabled = false,
    this.biometrics = false,
    this.timeout = LockTimeout.immediately,
    this.pinLength = 4,
  });

  /// Length of the PIN (not secret): the lock screen unlocks automatically at this length.
  final int pinLength;
  final bool enabled;
  final bool biometrics;
  final LockTimeout timeout;
}

enum PinCheck { ok, wrong, lockedOut }

class PinResult {
  const PinResult(this.check, {this.retryAfterSeconds = 0});
  final PinCheck check;
  final int retryAfterSeconds;
}

/// Stores the app-lock settings and the salted PIN hash in secure storage.
/// Everything lives there (not in the database), so a restored backup can
/// never bring back a lock whose PIN no longer exists.
class AppLockService {
  AppLockService(this._kv, {DateTime Function()? clock, this.iterations = 10000})
    : _now = clock ?? DateTime.now;

  final SecureKv _kv;
  final DateTime Function() _now;
  final int iterations;

  static const _kEnabled = 'applock.enabled';
  static const _kBio = 'applock.biometrics';
  static const _kTimeout = 'applock.timeout';
  static const _kSalt = 'applock.salt';
  static const _kHash = 'applock.hash';
  static const _kLen = 'applock.length';
  static const _kFailed = 'applock.failed';
  static const _kLockedUntil = 'applock.locked_until';

  Future<LockConfig> loadConfig() async {
    final hasPin = await _kv.read(_kHash) != null;
    final enabled = (await _kv.read(_kEnabled)) == '1' && hasPin;
    final timeoutName = await _kv.read(_kTimeout);
    return LockConfig(
      enabled: enabled,
      pinLength: int.tryParse(await _kv.read(_kLen) ?? '') ?? 4,
      biometrics: (await _kv.read(_kBio)) == '1',
      timeout: LockTimeout.values.firstWhere(
        (t) => t.name == timeoutName,
        orElse: () => LockTimeout.immediately,
      ),
    );
  }

  /// Turns the lock on with a new PIN (4 to 6 digits).
  Future<void> enable(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits.');
    await _storePin(pin);
    await _kv.write(_kEnabled, '1');
  }

  Future<void> changePin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits.');
    await _storePin(pin);
  }

  Future<void> _storePin(String pin) async {
    final salt = generateSalt();
    final hash = hashPin(pin, salt, iterations: iterations);
    await _kv.write(_kLen, '${pin.length}');
    await _kv.write(_kSalt, base64Encode(salt));
    await _kv.write(_kHash, base64Encode(hash));
    await _resetFailures();
  }

  /// Checks a PIN, with growing delays after repeated mistakes.
  Future<PinResult> verify(String pin) async {
    final until = int.tryParse(await _kv.read(_kLockedUntil) ?? '');
    if (until != null) {
      final remaining =
          (until - _now().millisecondsSinceEpoch + 999) ~/ 1000;
      if (remaining > 0) return PinResult(PinCheck.lockedOut, retryAfterSeconds: remaining);
    }
    final saltB64 = await _kv.read(_kSalt);
    final hashB64 = await _kv.read(_kHash);
    if (saltB64 == null || hashB64 == null) return const PinResult(PinCheck.wrong);
    final candidate = hashPin(
      pin,
      Uint8List.fromList(base64Decode(saltB64)),
      iterations: iterations,
    );
    if (constantTimeEquals(candidate, base64Decode(hashB64))) {
      await _resetFailures();
      return const PinResult(PinCheck.ok);
    }
    final failed = (int.tryParse(await _kv.read(_kFailed) ?? '') ?? 0) + 1;
    await _kv.write(_kFailed, '$failed');
    final wait = lockoutSeconds(failed);
    if (wait > 0) {
      await _kv.write(
        _kLockedUntil,
        '${_now().millisecondsSinceEpoch + wait * 1000}',
      );
      return PinResult(PinCheck.lockedOut, retryAfterSeconds: wait);
    }
    return const PinResult(PinCheck.wrong);
  }

  Future<void> _resetFailures() async {
    await _kv.delete(_kFailed);
    await _kv.delete(_kLockedUntil);
  }

  Future<void> setBiometrics(bool on) => _kv.write(_kBio, on ? '1' : '0');
  Future<void> setTimeout(LockTimeout t) => _kv.write(_kTimeout, t.name);

  /// Turns the lock off and forgets the PIN.
  Future<void> disable() => clearAll();

  Future<void> clearAll() async {
    for (final k in [_kEnabled, _kBio, _kTimeout, _kLen, _kSalt, _kHash, _kFailed, _kLockedUntil]) {
      await _kv.delete(k);
    }
  }
}
