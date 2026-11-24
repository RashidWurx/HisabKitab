import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/utils/money.dart';

void main() {
  group('Money.format', () {
    test('whole rupees have no decimals', () {
      expect(Money.format(1250000), 'Rs 12,500');
      expect(Money.format(0), 'Rs 0');
    });
    test('shows decimals only when present', () {
      expect(Money.format(1250050), 'Rs 12,500.50');
      expect(Money.format(1250005), 'Rs 12,500.05');
    });
    test('negative values', () {
      expect(Money.format(-200000), '-Rs 2,000');
    });
  });

  group('Money.parse', () {
    test('parses rupees and decimals into paisa', () {
      expect(Money.parse('12,500'), 1250000);
      expect(Money.parse('12500.5'), 1250050);
      expect(Money.parse('0.05'), 5);
    });
    test('rejects bad input', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1.234'), isNull);
      expect(Money.parse('-5'), isNull);
    });
  });
}
