import 'package:flutter/material.dart';

class LocaleProfile {
  const LocaleProfile({
    required this.locale,
    required this.countryCode,
    required this.baseCurrency,
    required this.dateFormat,
    required this.numberFormat,
    required this.currencyFormat,
  });

  final Locale locale;
  final String countryCode;
  final String baseCurrency;
  final String dateFormat;
  final String numberFormat;
  final String currencyFormat;

  String get localeTag => locale.countryCode == null || locale.countryCode!.isEmpty
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';

  LocaleProfile copyWith({
    Locale? locale,
    String? countryCode,
    String? baseCurrency,
    String? dateFormat,
    String? numberFormat,
    String? currencyFormat,
  }) {
    return LocaleProfile(
      locale: locale ?? this.locale,
      countryCode: countryCode ?? this.countryCode,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      dateFormat: dateFormat ?? this.dateFormat,
      numberFormat: numberFormat ?? this.numberFormat,
      currencyFormat: currencyFormat ?? this.currencyFormat,
    );
  }
}
