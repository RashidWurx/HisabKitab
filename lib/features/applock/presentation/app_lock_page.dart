import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/widgets.dart';
import '../application/app_lock_controller.dart';
import '../data/app_lock_service.dart';
import '../domain/pin_logic.dart';
import 'pin_pad.dart';

class AppLockPage extends ConsumerStatefulWidget {
  const AppLockPage({super.key});

  @override
  ConsumerState<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends ConsumerState<AppLockPage> {
  bool? _bioAvailable;

  @override
  void initState() {
    super.initState();
    ref.read(appLockProvider.notifier).biometricsAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _turnOn() async {
    final understood = await confirmDialog(
      context,
      title: 'Before you turn this on',
      message:
          'If you forget your PIN, nobody can recover it, not even us. The only way back in is to erase all data on this phone and restore a backup. Make a backup first.',
      confirmLabel: 'I understand',
    );
    if (!understood || !mounted) return;
    final pin = await context.push<String>('/settings/app-lock/setup');
    if (pin != null && mounted) {
      await ref.read(appLockProvider.notifier).enable(pin);
      if (mounted) showMessage(context, 'App lock is on');
    }
  }

  Future<void> _changePin() async {
    if (!await _verify('Enter your current PIN') || !mounted) return;
    final pin = await context.push<String>('/settings/app-lock/setup');
    if (pin != null && mounted) {
      await ref.read(appLockProvider.notifier).changePin(pin);
      if (mounted) showMessage(context, 'PIN changed');
    }
  }

  Future<void> _turnOff() async {
    if (!await _verify('Enter your PIN to turn off') || !mounted) return;
    await ref.read(appLockProvider.notifier).disable();
    if (mounted) showMessage(context, 'App lock is off');
  }

  /// Asks for the current PIN in a sheet. True when it is correct.
  Future<bool> _verify(String title) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VerifySheet(title: title),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final c = lock.config;
    final notifier = ref.read(appLockProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(c.enabled ? Icons.lock : Icons.lock_open_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.enabled ? 'App lock is on' : 'App lock is off',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.enabled
                      ? 'Hisaab asks for your PIN when you open it. Its content is hidden in the recent apps screen.'
                      : 'Protect your money data with a 4 to 6 digit PIN, and optionally your fingerprint or face.',
                ),
                const SizedBox(height: 14),
                if (!c.enabled)
                  FilledButton(onPressed: _turnOn, child: const Text('Set a PIN'))
                else
                  OutlinedButton(onPressed: _turnOff, child: const Text('Turn off')),
              ],
            ),
          ),
          if (c.enabled) ...[
            const SectionTitle('Lock after'),
            RadioGroup<LockTimeout>(
              groupValue: c.timeout,
              onChanged: (v) {
                if (v != null) notifier.setTimeout(v);
              },
              child: Column(
                children: [
                  for (final t in LockTimeout.values)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<LockTimeout>(
                        value: t,
                        title: Text(t.label),
                      ),
                    ),
                ],
              ),
            ),
            const SectionTitle('Unlock'),
            Card(
              child: SwitchListTile(
                title: const Text('Fingerprint / Face ID'),
                subtitle: Text(
                  _bioAvailable == false
                      ? 'No fingerprint or face is set up on this phone'
                      : 'Use your fingerprint or face instead of typing the PIN',
                ),
                value: c.biometrics,
                onChanged: _bioAvailable == true
                    ? (v) async {
                        final ok = await notifier.setBiometrics(v);
                        if (!ok && context.mounted) {
                          showMessage(context, 'Biometrics were not confirmed.');
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Change PIN'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePin,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Forgot your PIN? The only way back in is to erase all data and restore a backup.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet that checks the current PIN.
class _VerifySheet extends ConsumerStatefulWidget {
  const _VerifySheet({required this.title});

  final String title;

  @override
  ConsumerState<_VerifySheet> createState() => _VerifySheetState();
}

class _VerifySheetState extends ConsumerState<_VerifySheet> {
  String _pin = '';
  String? _error;

  Future<void> _digit(String d) async {
    final length = ref.read(appLockProvider).config.pinLength;
    if (_pin.length >= length) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == length) {
      final r = await ref.read(appLockProvider.notifier).verifyPin(_pin);
      if (!mounted) return;
      if (r.check == PinCheck.ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _pin = '';
          _error = r.check == PinCheck.lockedOut
              ? 'Too many tries. Wait ${r.retryAfterSeconds} s'
              : 'Wrong PIN';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = ref.watch(appLockProvider).config.pinLength;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            PinDots(filled: _pin.length, total: length, error: _error != null),
            SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  _error ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
            PinPad(
              onDigit: _digit,
              onBackspace: () => setState(() {
                if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose a new PIN: type it, then type it again. Pops with the PIN.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String _pin = '';
  String? _first;
  String? _error;

  void _digit(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _next() {
    if (!isValidPin(_pin)) return;
    if (_first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
      });
    } else if (_pin == _first) {
      Navigator.pop(context, _pin);
    } else {
      setState(() {
        _first = null;
        _pin = '';
        _error = 'The two PINs did not match. Start again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(confirming ? 'Confirm your PIN' : 'Choose a PIN'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              confirming
                  ? 'Type the same PIN again'
                  : 'Use 4 to 6 digits you will remember',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            PinDots(filled: _pin.length, total: 6, error: _error != null),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  _error ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
            const Spacer(),
            PinPad(
              onDigit: _digit,
              onBackspace: () => setState(() {
                if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                onPressed: isValidPin(_pin) ? _next : null,
                child: Text(confirming ? 'Confirm' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
