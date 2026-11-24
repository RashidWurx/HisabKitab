import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Row of dots showing how many digits were typed.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.filled,
    required this.total,
    this.color,
    this.error = false,
  });

  final int filled;
  final int total;
  final Color? color;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = error
        ? Theme.of(context).colorScheme.error
        : (color ?? Theme.of(context).colorScheme.onSurface);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? c : Colors.transparent,
              border: Border.all(color: c, width: 2),
            ),
          ),
      ],
    );
  }
}

/// Number keypad. Calls [onDigit] / [onBackspace]. The bottom-left key can
/// hold an extra action (e.g. the fingerprint button).
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leading,
    this.foreground,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? leading;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Theme.of(context).colorScheme.onSurface;
    Widget key(String digit) => _Key(
      onTap: () {
        HapticFeedback.selectionClick();
        onDigit(digit);
      },
      child: Text(
        digit,
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: fg),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Key(onTap: null, child: leading ?? const SizedBox.shrink()),
            key('0'),
            _Key(
              onTap: onBackspace,
              child: Icon(Icons.backspace_outlined, color: fg),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        child: SizedBox(width: 76, height: 76, child: Center(child: child)),
      ),
    );
  }
}
