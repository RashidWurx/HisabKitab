import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/providers.dart';
import '../data/app_lock_service.dart';
import '../domain/pin_logic.dart';

class AppLockState {
  const AppLockState({
    this.ready = false,
    this.config = const LockConfig(),
    this.locked = false,
    this.covered = false,
  });

  /// The lock settings have been read (the app shows nothing until then).
  final bool ready;
  final LockConfig config;

  /// The lock screen is showing.
  final bool locked;

  /// A privacy cover hides the app (app switcher, between background states).
  final bool covered;

  AppLockState copyWith({
    bool? ready,
    LockConfig? config,
    bool? locked,
    bool? covered,
  }) => AppLockState(
    ready: ready ?? this.ready,
    config: config ?? this.config,
    locked: locked ?? this.locked,
    covered: covered ?? this.covered,
  );
}

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(FlutterSecureKv()),
);

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

class AppLockController extends Notifier<AppLockState> {
  static const _privacy = MethodChannel('hisaab/privacy');

  final LocalAuthentication _auth = LocalAuthentication();
  DateTime? _backgroundedAt;
  bool _authenticating = false;

  AppLockService get _service => ref.read(appLockServiceProvider);

  @override
  AppLockState build() {
    Future.microtask(_init);
    return const AppLockState();
  }

  Future<void> _init() async {
    final config = await _service.loadConfig();
    state = AppLockState(ready: true, config: config, locked: config.enabled);
    await _applySecure(config.enabled);
  }

  /// Hides the app in the recent-apps screen (Android FLAG_SECURE).
  Future<void> _applySecure(bool on) async {
    try {
      await _privacy.invokeMethod<void>('setSecure', {'on': on});
    } on MissingPluginException {
      // iOS / tests: the privacy cover handles it.
    } catch (_) {}
  }

  Future<void> _reload({bool? locked}) async {
    final config = await _service.loadConfig();
    state = state.copyWith(config: config, locked: locked ?? state.locked);
    await _applySecure(config.enabled);
  }

  // ---- lifecycle -----------------------------------------------------------

  /// App is leaving the foreground (also fires for system dialogs).
  void onInactive() {
    if (state.config.enabled && !state.covered) {
      state = state.copyWith(covered: true);
    }
  }

  void onPaused() {
    if (!state.config.enabled || _authenticating) return;
    _backgroundedAt ??= DateTime.now();
    onInactive();
  }

  void onResumed() {
    if (_authenticating) {
      state = state.copyWith(covered: false);
      return;
    }
    var locked = state.locked;
    if (state.config.enabled && !locked) {
      locked = shouldLockOnResume(
        lockEnabled: true,
        backgroundedAt: _backgroundedAt,
        now: DateTime.now(),
        timeout: state.config.timeout,
      );
    }
    _backgroundedAt = null;
    state = state.copyWith(locked: locked, covered: false);
  }

  // ---- unlocking -----------------------------------------------------------

  Future<PinResult> unlockWithPin(String pin) async {
    final result = await _service.verify(pin);
    if (result.check == PinCheck.ok) {
      state = state.copyWith(locked: false);
    }
    return result;
  }

  Future<bool> biometricsAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fingerprint / Face ID. Returns true (and unlocks) on success.
  Future<bool> unlockWithBiometrics() async {
    if (!state.config.biometrics) return false;
    return _biometricCheck('Unlock Hisaab', unlock: true);
  }

  Future<bool> _biometricCheck(String reason, {required bool unlock}) async {
    _authenticating = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      if (ok && unlock) state = state.copyWith(locked: false);
      return ok;
    } catch (_) {
      return false;
    } finally {
      _authenticating = false;
      _backgroundedAt = null;
    }
  }

  // ---- settings ------------------------------------------------------------

  /// Turn the lock on. Keeps the user inside (unlocked) for this session.
  Future<void> enable(String pin) async {
    await _service.enable(pin);
    await _reload(locked: false);
  }

  Future<void> changePin(String pin) async {
    await _service.changePin(pin);
    await _reload();
  }

  Future<PinResult> verifyPin(String pin) => _service.verify(pin);

  Future<void> disable() async {
    await _service.disable();
    await _reload(locked: false);
  }

  Future<void> setTimeout(LockTimeout t) async {
    await _service.setTimeout(t);
    await _reload();
  }

  /// Turning biometrics on first proves the finger/face works.
  Future<bool> setBiometrics(bool on) async {
    if (on) {
      final ok = await _biometricCheck('Confirm to use biometrics', unlock: false);
      if (!ok) return false;
    }
    await _service.setBiometrics(on);
    await _reload();
    return true;
  }

  /// "Forgot PIN": erases ALL app data and the PIN. The user can then restore
  /// a backup.
  Future<void> resetEverything() async {
    await ref.read(settingsRepositoryProvider).deleteAllData();
    await _service.clearAll();
    await _reload(locked: false);
  }
}
