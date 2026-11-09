import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

String extractKazakhNationalDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 10 &&
      (digits.startsWith('7') || digits.startsWith('8'))) {
    digits = digits.substring(1);
  }
  if (digits.length > 10) {
    digits = digits.substring(0, 10);
  }
  return digits;
}

String formatKazakhNationalPhoneInput(String raw) {
  final digits = extractKazakhNationalDigits(raw);
  if (digits.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i == 3 || i == 6 || i == 8) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatKazakhPhoneInput(String raw) {
  final national = formatKazakhNationalPhoneInput(raw);
  if (national.isEmpty) {
    return '';
  }
  return '+7 $national';
}

class KazakhPhoneInputFormatter extends TextInputFormatter {
  const KazakhPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatKazakhNationalPhoneInput(newValue.text);
    final clampedBaseOffset = newValue.selection.baseOffset.clamp(
      0,
      newValue.text.length,
    );
    final digitsBeforeCursor = extractKazakhNationalDigits(
      newValue.text.substring(0, clampedBaseOffset),
    ).length;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _selectionOffsetForDigitCount(formatted, digitsBeforeCursor),
      ),
    );
  }

  int _selectionOffsetForDigitCount(String formatted, int digitCount) {
    if (digitCount <= 0) {
      return 0;
    }

    var seenDigits = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        seenDigits++;
        if (seenDigits == digitCount) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }
}

String normalizeKazakhPhone(String raw) {
  final digits = extractKazakhNationalDigits(raw);
  if (digits.length == 10) {
    return '+7$digits';
  }
  return raw.trim();
}

bool isKazakhPhoneValid(String raw) {
  final normalized = normalizeKazakhPhone(raw);
  return RegExp(r'^\+7\d{10}$').hasMatch(normalized);
}

String formatPhoneDisplay(String raw) {
  final normalized = normalizeKazakhPhone(raw);
  if (!RegExp(r'^\+7\d{10}$').hasMatch(normalized)) {
    if (extractKazakhNationalDigits(raw).isEmpty) {
      return '';
    }
    return formatKazakhPhoneInput(raw);
  }
  final digits = normalized.replaceAll(RegExp(r'\D'), '');
  return '+${digits[0]} ${digits.substring(1, 4)} ${digits.substring(4, 7)} '
      '${digits.substring(7, 9)} ${digits.substring(9, 11)}';
}

double asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? fallback;
}

String formatEnergy(double valueKwh, String localeTag, {int digits = 1}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: localeTag,
    decimalDigits: digits,
  );
  return '${format.format(valueKwh)} kWh';
}

String formatPower(double valueKw, String localeTag, {int digits = 1}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: localeTag,
    decimalDigits: digits,
  );
  return '${format.format(valueKw)} kW';
}

String formatPercent(double value, String localeTag, {int digits = 0}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: localeTag,
    decimalDigits: digits,
  );
  return '${format.format(value * 100)}%';
}

String formatNumber(double value, String localeTag, {int digits = 0}) {
  final format = NumberFormat.decimalPatternDigits(
    locale: localeTag,
    decimalDigits: digits,
  );
  return format.format(value);
}

String formatCompact(double value, String localeTag) {
  return NumberFormat.compact(locale: localeTag).format(value);
}

String formatDateShort(DateTime dateTime, String localeTag) {
  return DateFormat.MMMd(localeTag).format(dateTime);
}

String formatDateLong(DateTime dateTime, String localeTag) {
  return DateFormat.yMMMMd(localeTag).format(dateTime);
}

String formatDateWithWeekday(DateTime dateTime, String localeTag) {
  return DateFormat('EEEE, d MMMM', localeTag).format(dateTime);
}

String formatDayLabel(DateTime dateTime, String localeTag) {
  return DateFormat.E(localeTag).format(dateTime);
}

String formatDateTimeLabel(DateTime dateTime, String localeTag) {
  return DateFormat('dd MMM, HH:mm', localeTag).format(dateTime);
}

String formatTimeLabel(DateTime dateTime, String localeTag) {
  return DateFormat('HH:mm', localeTag).format(dateTime);
}
