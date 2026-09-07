import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/utils/currency_formatter.dart';

void main() {
  group('formatAmount', () {
    test('formats numbers with thousands commas and two decimal places', () {
      expect(formatAmount(20000), '20,000.00');
      expect(formatAmount(1146.91), '1,146.91');
      expect(formatAmount(209838.03), '209,838.03');
      expect(formatAmount(182.96), '182.96');
      expect(formatAmount(0), '0.00');
      expect(formatAmount(50), '50.00');
      expect(formatAmount(1000000), '1,000,000.00');
    });

    test('supports trimZeroDecimals and custom decimals', () {
      expect(formatAmount(20000, trimZeroDecimals: true), '20,000');
      expect(formatAmount(20000.50, trimZeroDecimals: true), '20,000.50');
      expect(formatAmount(150, decimals: 0), '150');
      expect(formatAmount(1500, decimals: 0), '1,500');
      expect(formatAmount(null), '');
    });

    test('handles negative amounts', () {
      expect(formatAmount(-3000), '-3,000.00');
      expect(formatAmount(-3000, trimZeroDecimals: true), '-3,000');
    });
  });

  group('formatInputAmount', () {
    test('formats typed integer strings with commas', () {
      expect(formatInputAmount('20000'), '20,000');
      expect(formatInputAmount('1000000'), '1,000,000');
      expect(formatInputAmount('50'), '50');
      expect(formatInputAmount(''), '');
    });

    test('preserves trailing decimal dots and digits', () {
      expect(formatInputAmount('20000.'), '20,000.');
      expect(formatInputAmount('20000.5'), '20,000.5');
      expect(formatInputAmount('20000.50'), '20,000.50');
    });
  });

  group('parseAmount', () {
    test('parses formatted strings with commas', () {
      expect(parseAmount('20,000'), 20000.0);
      expect(parseAmount('1,146.91'), 1146.91);
      expect(parseAmount('209,838.03'), 209838.03);
      expect(parseAmount(''), null);
      expect(parseAmount(null), null);
    });
  });

  group('ThousandsSeparatorInputFormatter', () {
    final formatter = ThousandsSeparatorInputFormatter();

    test('formats input as thousands commas are entered', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '2000', selection: TextSelection.collapsed(offset: 4)),
        const TextEditingValue(text: '20000', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(res.text, '20,000');
      expect(res.selection.baseOffset, 6);
    });

    test('handles decimal point entry', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '20,000', selection: TextSelection.collapsed(offset: 6)),
        const TextEditingValue(text: '20,000.', selection: TextSelection.collapsed(offset: 7)),
      );
      expect(res.text, '20,000.');
      expect(res.selection.baseOffset, 7);
    });

    test('blocks multiple decimal points', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '20,000.5', selection: TextSelection.collapsed(offset: 8)),
        const TextEditingValue(text: '20,000.5.', selection: TextSelection.collapsed(offset: 9)),
      );
      expect(res.text, '20,000.5');
    });

    test('limits decimal places to 2', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '20,000.50', selection: TextSelection.collapsed(offset: 9)),
        const TextEditingValue(text: '20,000.500', selection: TextSelection.collapsed(offset: 10)),
      );
      expect(res.text, '20,000.50');
    });
  });
}
