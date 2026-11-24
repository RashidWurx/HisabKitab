import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/app_lock_controller.dart';
import '../data/app_lock_service.dart';
import 'pin_pad.dart';

/// Wraps the whole app: shows the lock screen over it while locked, and a
/// plain cover while the app is in the app switcher.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        // While the lock is still loading, show nothing of the app.
        if (lock.ready) child else const ColoredBox(color: AppTheme.navy),
        if (lock.ready && lock.locked) const LockScreen(),
        if (lock.covered && lock.config.enabled && !lock.locked)
          const _PrivacyCover(),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.navy,
      child: Center(
        child: Icon(Icons.lock_outline, color: Colors.white54, size: 56),
      ),
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  bool _wrong = false;
  bool _busy = false;
  int _lockedSeconds = 0;
  Timer? _timer;
  bool _bioTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometrics() async {
    final lock = ref.read(appLockProvider);
    if (_bioTried || !lock.config.biometrics || !mounted) return;
    _bioTried = true;
    await ref.read(appLockProvider.notifier).unlockWithBiometrics();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _lockedSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _lockedSeconds = _lockedSeconds - 1);
      if (_lockedSeconds <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    final length = ref.read(appLockProvider).config.pinLength;
    if (_busy || _pin.length != length || _lockedSeconds > 0) return;
    setState(() => _busy = true);
    final result = await ref.read(appLockProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    switch (result.check) {
      case PinCheck.ok:
        break;
      case PinCheck.wrong:
        setState(() {
          _wrong = true;
          _pin = '';
        });
      case PinCheck.lockedOut:
        setState(() {
          _wrong = true;
          _pin = '';
        });
        _startCountdown(result.retryAfterSeconds);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _digit(String d) {
    final length = ref.read(appLockProvider).config.pinLength;
    if (_lockedSeconds > 0 || _pin.length >= length) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length == length) _submit();
  }

  Future<void> _forgot() async {
    // This screen sits above the app's Navigator, so dialogs need its context.
    final nav = rootNavigatorKey.currentContext;
    if (nav == null) return;
    final first = await confirmDialog(
      nav,
      title: 'Forgot your PIN?',
      message:
          'Hisaab cannot recover a PIN. The only way in is to erase all data on this phone and then restore a backup (Backup & restore).',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!first || !nav.mounted) return;
    final typed = await showTextDialog(
      nav,
      title: 'Type DELETE to confirm',
      hint: 'DELETE',
      confirmLabel: 'Erase all data',
      capitalization: TextCapitalization.characters,
    );
    if (typed == null || typed.trim().toUpperCase() != 'DELETE') return;
    await ref.read(appLockProvider.notifier).resetEverything();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final length = lock.config.pinLength;
    final locked = _lockedSeconds > 0;
    return Material(
      color: AppTheme.navy,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const Icon(Icons.lock_outline, color: Colors.white, size: 44),
            const SizedBox(height: 16),
            const Text(
              'Hisaab',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              locked
                  ? 'Too many tries. Wait $_lockedSeconds s'
                  : _wrong
                  ? 'Wrong PIN, try again'
                  : 'Enter your PIN',
              style: TextStyle(
                color: _wrong ? const Color(0xFFFF9A92) : Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            PinDots(
              filled: _pin.length,
              total: length,
              color: Colors.white,
              error: _wrong,
            ),
            const Spacer(),
            PinPad(
              foreground: Colors.white,
              onDigit: _digit,
              onBackspace: () => setState(() {
                if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
              }),
              leading: lock.config.biometrics
                  ? IconButton(
                      iconSize: 34,
                      color: Colors.white,
                      icon: const Icon(Icons.fingerprint),
                      onPressed: () => ref
                          .read(appLockProvider.notifier)
                          .unlockWithBiometrics(),
                    )
                  : null,
            ),
            TextButton(
              onPressed: _forgot,
              child: const Text(
                'Forgot PIN?',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
