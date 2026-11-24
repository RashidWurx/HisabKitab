import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/money.dart';
import 'icon_registry.dart';

/// Money text. Green when positive, red when negative, ink when [neutral]
/// or zero. Pass signed paisa (expenses as negatives).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.paisa, {
    super.key,
    this.style,
    this.neutral = false,
    this.forceColor,
  });

  final int paisa;
  final TextStyle? style;
  final bool neutral;
  final Color? forceColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color =
        forceColor ??
        (neutral || paisa == 0
            ? null
            : (paisa < 0 ? colors.negative : colors.positive));
    return Text(
      Money.format(paisa),
      style: (style ?? const TextStyle()).copyWith(color: color),
    );
  }
}

/// Outlined card used across the app (matches the mockups).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Square outlined icon, as used for accounts, sources and categories.
class IconBox extends StatelessWidget {
  const IconBox({
    super.key,
    required this.iconKey,
    this.color,
    this.size = 44,
    this.filled = false,
  });

  final String iconKey;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurface;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(
        iconFor(iconKey),
        size: size * 0.52,
        color: filled ? scheme.surface : c,
      ),
    );
  }
}

/// Friendly empty state with an optional action button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(180, 48),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Label/value row with a divider, as in the "Remaining / Total / Received"
/// blocks of the mockups.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueWidget});

  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          valueWidget ??
              Text(
                value ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ],
      ),
    );
  }
}

/// Big amount entry ("Rs 10,000") with a number keypad.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.onChanged,
    this.autofocus = true,
    this.label = 'Amount',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            prefixText: 'Rs ',
            prefixStyle: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
            ),
            hintText: '0',
            hintStyle: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: scheme.outlineVariant,
            ),
            border: const UnderlineInputBorder(),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ],
    );
  }
}

/// A tappable field that looks like a dropdown (opens a sheet or picker).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    this.iconKey,
    this.iconColor,
    this.leading,
    required this.value,
    this.placeholder = 'Choose',
    this.onTap,
    this.trailing = Icons.keyboard_arrow_down,
  });

  final String label;
  final String? iconKey;
  final Color? iconColor;
  final Widget? leading;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
              color: scheme.surfaceContainerLowest,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)]
                else if (iconKey != null) ...[
                  Icon(iconFor(iconKey!), color: iconColor, size: 22),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    value ?? placeholder,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: value == null ? scheme.outline : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(trailing, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small coloured status chip (pending / partial / overdue / settled).
class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

/// Shows a snackbar-style message.
void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Yes/no dialog. Returns true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).extension<AppColors>()!.negative,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Parsed amount helper for text controllers. Null when empty/invalid.
int? parseAmount(String text) => Money.parse(text);
