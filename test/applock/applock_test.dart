import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/features/applock/data/app_lock_service.dart';
import 'package:hisaab/features/applock/domain/pin_logic.dart';

void main() {
  group('PIN hashing', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));

    test('same PIN and salt give the same hash; different PIN or salt do not',
        () {
      final a = hashPin('1234', salt, iterations: 50);
      expect(hashPin('1234', salt, iterations: 50), a);
      expect(hashPin('1235', salt, iterations: 50), isNot(a));
      final other = Uint8List.fromList(List.generate(16, (i) => i + 1));
      expect(hashPin('1234', other, iterations: 50), isNot(a));
      expect(a.length, 32);
    });

    test('matches the PBKDF2-HMAC-SHA256 reference vector', () {
      // RFC 7914 section 11: PBKDF2-HMAC-SHA-256, P="passwd", S="salt", c=1
      final out = hashPin(
        'passwd',
        Uint8List.fromList('salt'.codeUnits),
        iterations: 1,
      );
      final hex = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });

    test('constant time compare', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('PIN rules: 4 to 6 digits', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
    });
  });

  group('lockout and timeout', () {
    test('lockout grows after 5 wrong tries', () {
      expect(lockoutSeconds(0), 0);
      expect(lockoutSeconds(4), 0);
      expect(lockoutSeconds(5), 30);
      expect(lockoutSeconds(6), 60);
      expect(lockoutSeconds(7), 300);
      expect(lockoutSeconds(50), 3600);
    });

    test('lock after background: immediately / 1 min / 5 min', () {
      final t0 = DateTime(2026, 11, 25, 10);
      bool lock(Duration away, LockTimeout timeout, {bool enabled = true}) =>
          shouldLockOnResume(
            lockEnabled: enabled,
            backgroundedAt: t0,
            now: t0.add(away),
            timeout: timeout,
          );
      expect(lock(Duration.zero, LockTimeout.immediately), isTrue);
      expect(lock(const Duration(seconds: 59), LockTimeout.oneMinute), isFalse);
      expect(lock(const Duration(seconds: 60), LockTimeout.oneMinute), isTrue);
      expect(lock(const Duration(minutes: 4), LockTimeout.fiveMinutes), isFalse);
      expect(lock(const Duration(minutes: 5), LockTimeout.fiveMinutes), isTrue);
      expect(lock(const Duration(hours: 5), LockTimeout.immediately, enabled: false), isFalse);
      expect(
        shouldLockOnResume(
          lockEnabled: true,
          backgroundedAt: null,
          now: t0,
          timeout: LockTimeout.fiveMinutes,
        ),
        isTrue,
      );
    });
  });

  group('AppLockService', () {
    late MemoryKv kv;
    late DateTime now;
    late AppLockService service;

    setUp(() {
      kv = MemoryKv();
      now = DateTime(2026, 11, 25, 10);
      service = AppLockService(kv, clock: () => now, iterations: 20);
    });

    test('off by default; on after enable; only a hash is stored', () async {
      expect((await service.loadConfig()).enabled, isFalse);
      await service.enable('4821');
      expect((await service.loadConfig()).enabled, isTrue);
      expect(kv.values.values.any((v) => v.contains('4821')), isFalse);
      expect(kv.values.containsKey('applock.salt'), isTrue);
    });

    test('right and wrong PIN', () async {
      await service.enable('4821');
      expect((await service.verify('4821')).check, PinCheck.ok);
      expect((await service.verify('0000')).check, PinCheck.wrong);
    });

    test('5 wrong tries lock the pad, and time unlocks it', () async {
      await service.enable('4821');
      for (var i = 0; i < 4; i++) {
        expect((await service.verify('1111')).check, PinCheck.wrong);
      }
      final fifth = await service.verify('1111');
      expect(fifth.check, PinCheck.lockedOut);
      expect(fifth.retryAfterSeconds, 30);
      // Even the right PIN is refused while locked out.
      expect((await service.verify('4821')).check, PinCheck.lockedOut);
      now = now.add(const Duration(seconds: 31));
      expect((await service.verify('4821')).check, PinCheck.ok);
      // Success resets the counter.
      expect((await service.verify('1111')).check, PinCheck.wrong);
    });

    test('change PIN, biometrics and timeout settings', () async {
      await service.enable('4821');
      await service.changePin('135790');
      expect((await service.verify('4821')).check, PinCheck.wrong);
      expect((await service.verify('135790')).check, PinCheck.ok);
      await service.setBiometrics(true);
      await service.setTimeout(LockTimeout.fiveMinutes);
      final c = await service.loadConfig();
      expect(c.biometrics, isTrue);
      expect(c.timeout, LockTimeout.fiveMinutes);
    });

    test('disable forgets everything', () async {
      await service.enable('4821');
      await service.disable();
      final c = await service.loadConfig();
      expect(c.enabled, isFalse);
      expect(kv.values, isEmpty);
    });

    test('an "enabled" flag without a PIN hash is treated as off', () async {
      await kv.write('applock.enabled', '1'); // e.g. after a reinstall
      expect((await service.loadConfig()).enabled, isFalse);
    });

    test('rejects bad PINs', () async {
      expect(() => service.enable('12'), throwsArgumentError);
    });
  });
}
