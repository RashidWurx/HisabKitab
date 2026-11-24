import 'package:intl/intl.dart';

/// Money is stored as integer paisa (rupees x 100). Never use double for money.
abstract final class Money {
  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');

  /// Formats paisa as `Rs 12,500`, `Rs 12,500.50`, or `-Rs 2,000`.
  /// Decimals are shown only when the amount has them.
  static String format(int paisa) {
    final negative = paisa < 0;
    final abs = paisa.abs();
    final rupees = abs ~/ 100;
    final rest = abs % 100;
    final whole = _whole.format(rupees);
    final body = rest == 0
        ? whole
        : '$whole.${rest.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}Rs $body';
  }

  /// Parses user input like `12,500` or `12500.5` into paisa.
  /// Returns null when the text is not a valid amount (max 2 decimals).
  static int? parse(String input) {
    final text = input.replaceAll(',', '').replaceAll(' ', '').trim();
    if (text.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final rupees = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return rupees * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
  }
}
