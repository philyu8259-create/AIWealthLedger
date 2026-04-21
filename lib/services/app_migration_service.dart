import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_profile_service.dart';

class AppMigrationService {
  AppMigrationService(this._prefs, this._profileService);

  final SharedPreferences _prefs;
  final AppProfileService _profileService;

  Future<void> run({required Locale deviceLocale}) async {
    await _profileService.ensureInitialized(deviceLocale: deviceLocale);
    await _migrateMetadata();
    await _migrateAccountEntries();
    await _migrateAssets();
    await _migrateStockPositions();
  }

  Future<void> _migrateMetadata() async {
    final schemaVersion = _prefs.getInt('app_schema_version') ?? 0;
    if (schemaVersion < AppProfileService.schemaVersion) {
      await _prefs.setInt('app_schema_version', AppProfileService.schemaVersion);
    }

    final migrationVersion = _prefs.getInt('app_migration_version') ?? 0;
    if (migrationVersion < AppProfileService.migrationVersion) {
      await _prefs.setInt(
        'app_migration_version',
        AppProfileService.migrationVersion,
      );
    }
  }

  Future<void> _migrateAccountEntries() async {
    const keys = ['account_entries', 'demo_accounting_entries'];
    final profile = _profileService.currentProfile.localeProfile;
    for (final key in keys) {
      await _migrateJsonList(key, (item) {
        final amount = _tryParseDouble(
              item['amount'] ?? item['baseAmount'] ?? item['originalAmount'],
            ) ??
            0;
        final originalCurrency =
            (item['originalCurrency'] as String?) ?? profile.baseCurrency;
        final baseCurrency =
            (item['baseCurrency'] as String?) ?? profile.baseCurrency;
        final originalAmount =
            _tryParseDouble(item['originalAmount']) ?? amount;
        final baseAmount = _tryParseDouble(item['baseAmount']) ?? amount;
        final fxRate = _tryParseDouble(item['fxRate']) ??
            (originalAmount == 0 ? 1.0 : baseAmount / originalAmount);
        return {
          ...item,
          'amount': baseAmount,
          'categoryId': item['categoryId'] ?? item['category'] ?? 'other',
          'originalAmount': originalAmount,
          'originalCurrency': originalCurrency,
          'baseAmount': baseAmount,
          'baseCurrency': baseCurrency,
          'fxRate': fxRate,
          'fxRateSource': item['fxRateSource'] ?? 'legacy',
          'sourceType': item['sourceType'] ?? 'manual',
          'locale': item['locale'] ?? profile.localeTag.replaceAll('_', '-'),
          'countryCode': item['countryCode'] ?? profile.countryCode,
        };
      });
    }
  }

  Future<void> _migrateAssets() async {
    final keys = _prefs
        .getKeys()
        .where(
          (key) =>
              key == 'assets' ||
              key == 'cloud_assets' ||
              key == 'demo_asset_accounts' ||
              key.startsWith('cloud_assets_v2_'),
        )
        .toList();
    final profile = _profileService.currentProfile.localeProfile;
    for (final key in keys) {
      await _migrateJsonList(key, (item) {
        return {
          ...item,
          'currency': item['currency'] ?? profile.baseCurrency,
          'locale': item['locale'] ?? profile.localeTag.replaceAll('_', '-'),
          'countryCode': item['countryCode'] ?? profile.countryCode,
        };
      });
    }
  }

  Future<void> _migrateStockPositions() async {
    final keys = _prefs
        .getKeys()
        .where(
          (key) =>
              key == 'stock_positions_v1' ||
              key == 'demo_stock_positions_v1' ||
              key.startsWith('stock_positions_v2_'),
        )
        .toList();
    for (final key in keys) {
      await _migrateJsonList(key, (item) {
        final exchange = (item['exchange'] ?? '').toString();
        return {
          ...item,
          'marketCurrency': item['marketCurrency'] ??
              _defaultStockCurrencyForExchange(exchange),
          'locale': item['locale'] ?? _defaultStockLocaleForExchange(exchange),
          'countryCode':
              item['countryCode'] ?? _defaultStockCountryForExchange(exchange),
        };
      });
    }
  }

  Future<void> _migrateJsonList(
    String key,
    Map<String, dynamic> Function(Map<String, dynamic>) transform,
  ) async {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final migrated = decoded
          .map((item) => transform(Map<String, dynamic>.from(item as Map)))
          .toList();
      await _prefs.setString(key, jsonEncode(migrated));
    } catch (_) {
      // 保持静默，避免因单个旧 key 数据损坏阻塞主流程。
    }
  }

  double? _tryParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _defaultStockCurrencyForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'USD';
    }
    return 'CNY';
  }

  String _defaultStockLocaleForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'en-US';
    }
    return 'zh-CN';
  }

  String _defaultStockCountryForExchange(String exchange) {
    final normalized = exchange.toUpperCase();
    if (normalized.contains('NASDAQ') ||
        normalized.contains('NYSE') ||
        normalized == 'US') {
      return 'US';
    }
    return 'CN';
  }
}
