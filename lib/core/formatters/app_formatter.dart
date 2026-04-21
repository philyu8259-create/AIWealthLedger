import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppFormatter {
  const AppFormatter._();

  static String currencySymbol({
    required String currencyCode,
    required Locale locale,
  }) {
    return NumberFormat.simpleCurrency(
      locale: _localeTag(locale),
      name: currencyCode,
    ).currencySymbol;
  }

  static String formatCurrency(
    num amount, {
    required String currencyCode,
    required Locale locale,
  }) {
    return NumberFormat.simpleCurrency(
      locale: _localeTag(locale),
      name: currencyCode,
    ).format(amount);
  }

  static String formatDecimal(
    num value, {
    required Locale locale,
    int decimalDigits = 2,
  }) {
    final pattern = decimalDigits <= 0
        ? '#,##0'
        : '#,##0.${'0' * decimalDigits}';
    return NumberFormat(pattern, _localeTag(locale)).format(value);
  }

  static String formatShortDate(DateTime date, {required Locale locale}) {
    return DateFormat.yMd(_localeTag(locale)).format(date);
  }

  static String formatMediumDate(DateTime date, {required Locale locale}) {
    return DateFormat.yMMMd(_localeTag(locale)).format(date);
  }

  static String _localeTag(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
}
