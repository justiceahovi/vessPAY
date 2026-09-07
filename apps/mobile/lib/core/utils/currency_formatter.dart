import 'package:flutter/services.dart';

/// Formats a numeric amount with commas for thousands and dots for decimals.
///
/// Examples:
/// - `formatAmount(20000)` -> `"20,000.00"`
/// - `formatAmount(20000, trimZeroDecimals: true)` -> `"20,000"`
/// - `formatAmount(1146.91)` -> `"1,146.91"`
/// - `formatAmount(209838.03)` -> `"209,838.03"`
/// - `formatAmount(null)` -> `""`
String formatAmount(
  num? amount, {
  int decimals = 2,
  bool trimZeroDecimals = false,
}) {
  if (amount == null) return '';
  final isNegative = amount < 0;
  final absAmount = amount.abs();
  final fixed = absAmount.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '';

  final buffer = StringBuffer();
  final intChars = intPart.split('').reversed.toList();
  for (int i = 0; i < intChars.length; i++) {
    if (i > 0 && i % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(intChars[i]);
  }
  final formattedInt = buffer.toString().split('').reversed.join('');

  String result = (isNegative ? '-' : '') + formattedInt;
  if (decimals > 0) {
    if (trimZeroDecimals && (decPart.isEmpty || int.tryParse(decPart) == 0)) {
      // Omit trailing zero decimals
    } else {
      result += '.$decPart';
    }
  }
  return result;
}

/// Formats a raw user-input string (which may be incomplete or partially typed)
/// with thousands comma separators, keeping dots for decimals.
///
/// Examples:
/// - `formatInputAmount("20000")` -> `"20,000"`
/// - `formatInputAmount("20000.")` -> `"20,000."`
/// - `formatInputAmount("20000.5")` -> `"20,000.5"`
/// - `formatInputAmount("20000.50")` -> `"20,000.50"`
String formatInputAmount(String input) {
  if (input.isEmpty) return '';
  final clean = input.replaceAll(',', '').trim();
  if (clean.isEmpty) return '';

  final isNegative = clean.startsWith('-');
  final unsigned = isNegative ? clean.substring(1) : clean;
  final parts = unsigned.split('.');
  var intPart = parts[0];
  final hasDecimal = parts.length > 1 || clean.endsWith('.');
  final decPart = parts.length > 1 ? parts[1] : '';

  if (intPart.length > 1 && intPart.startsWith('0')) {
    intPart = intPart.replaceFirst(RegExp(r'^0+'), '');
    if (intPart.isEmpty) intPart = '0';
  }

  final buffer = StringBuffer();
  final intChars = intPart.split('').reversed.toList();
  for (int i = 0; i < intChars.length; i++) {
    if (i > 0 && i % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(intChars[i]);
  }
  final formattedInt = buffer.toString().split('').reversed.join('');

  String result = (isNegative ? '-' : '') + formattedInt;
  if (hasDecimal) {
    result += '.$decPart';
  }
  return result;
}

/// Parses a formatted amount string (which may contain commas) into a double.
double? parseAmount(String? text) {
  if (text == null) return null;
  final clean = text.replaceAll(',', '').trim();
  if (clean.isEmpty) return null;
  return double.tryParse(clean);
}

/// A TextInputFormatter that automatically adds comma separators for thousands
/// while typing, supports decimal inputs with dot, and ensures smooth cursor behavior.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final int maxDecimalDigits;

  ThousandsSeparatorInputFormatter({this.maxDecimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String textToFormat = newValue.text;
    int cursorOffset = newValue.selection.end;

    // Detect if user backspaced a comma directly: e.g. "2|,000" -> user hits backspace
    if (oldValue.text.length - newValue.text.length == 1 &&
        oldValue.selection.start > 0 &&
        oldValue.selection.isCollapsed &&
        oldValue.text[oldValue.selection.start - 1] == ',') {
      final commaIndex = oldValue.selection.start - 1;
      if (commaIndex > 0) {
        final before = oldValue.text.substring(0, commaIndex - 1);
        final after = oldValue.text.substring(commaIndex);
        textToFormat = before + after;
        cursorOffset = commaIndex - 1;
      }
    }

    final clean = textToFormat.replaceAll(',', '').trim();

    // Reject invalid characters (only digits and at most one decimal point allowed)
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(clean)) {
      return oldValue;
    }

    final parts = clean.split('.');
    if (parts.length > 1 && parts[1].length > maxDecimalDigits) {
      return oldValue;
    }

    final formatted = formatInputAmount(textToFormat);

    // Calculate new cursor position based on non-comma characters before cursor
    int nonCommaBeforeCursor = 0;
    for (int i = 0; i < cursorOffset && i < textToFormat.length; i++) {
      if (textToFormat[i] != ',') {
        nonCommaBeforeCursor++;
      }
    }

    int newCursorOffset = 0;
    int nonCommaCounted = 0;
    while (newCursorOffset < formatted.length &&
        nonCommaCounted < nonCommaBeforeCursor) {
      if (formatted[newCursorOffset] != ',') {
        nonCommaCounted++;
      }
      newCursorOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorOffset),
    );
  }
}
