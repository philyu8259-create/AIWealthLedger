import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_flavor.dart';
import '../app/profile/app_profile.dart';
import '../app/profile/capability_profile.dart';
import '../app/profile/locale_profile.dart';

class AppProfileService extends ChangeNotifier {
  AppProfileService(this._prefs);

  final SharedPreferences _prefs;

  static const schemaVersion = 2;
  static const migrationVersion = 1;

  static const _schemaVersionKey = 'app_schema_version';
  static const _migrationVersionKey = 'app_migration_version';
  static const _modeKey = 'app_mode';
  static const _modeLockedKey = 'app_mode_locked';
  static const _localeKey = 'app_locale';
  static const _countryCodeKey = 'app_country_code';
  static const _baseCurrencyKey = 'app_base_currency';

  AppFlavor get flavor => _storedMode ?? AppFlavorX.buildFlavor;

  bool get isModeLocked => _prefs.getBool(_modeLockedKey) ?? false;

  List<Locale> get supportedLocales => const [
    Locale('zh', 'CN'),
    Locale('en', 'US'),
    Locale('en', 'GB'),
    Locale('en', 'AU'),
  ];

  Future<void> ensureInitialized({Locale? deviceLocale}) async {
    final previousStoredMode = _storedMode;
    final sessionExists = _hasExistingSession;
    final inferredMode = AppFlavorX.hasExplicitBuildFlavor
        ? AppFlavorX.buildFlavor
        : _inferMode(deviceLocale);
    final resolvedMode = _resolveEffectiveMode(
      inferredMode: inferredMode,
      sessionExists: sessionExists,
    );

    if (_prefs.getString(_modeKey) != resolvedMode.name) {
      await _prefs.setString(_modeKey, resolvedMode.name);
    }
    if (!_prefs.containsKey(_modeLockedKey)) {
      await _prefs.setBool(_modeLockedKey, sessionExists);
    }

    final fallback = _fallbackLocaleForFlavor(resolvedMode);
    final resolvedDeviceLocale = _normalizeDeviceLocale(
      deviceLocale,
      fallback,
      resolvedMode,
    );
    final initialLocale =
        resolvedMode == AppFlavor.cn ? fallback : resolvedDeviceLocale;
    final initialCountry =
        resolvedMode == AppFlavor.cn ? 'CN' : (initialLocale.countryCode ?? 'US');
    final initialCurrency = _defaultCurrencyForCountry(initialCountry);
    final shouldSeedModeDefaults = previousStoredMode == null;

    if (!_prefs.containsKey(_schemaVersionKey)) {
      await _prefs.setInt(_schemaVersionKey, schemaVersion);
    }
    if (!_prefs.containsKey(_migrationVersionKey)) {
      await _prefs.setInt(_migrationVersionKey, migrationVersion);
    }
    if (shouldSeedModeDefaults || !_prefs.containsKey(_localeKey)) {
      await _prefs.setString(_localeKey, _toStorageLocale(initialLocale));
    }
    if (shouldSeedModeDefaults || !_prefs.containsKey(_countryCodeKey)) {
      await _prefs.setString(_countryCodeKey, initialCountry);
    }
    if (shouldSeedModeDefaults || !_prefs.containsKey(_baseCurrencyKey)) {
      await _prefs.setString(_baseCurrencyKey, initialCurrency);
    }
  }

  Future<void> lockCurrentMode() async {
    await _prefs.setBool(_modeLockedKey, true);
    notifyListeners();
  }

  Future<void> switchMode(AppFlavor targetMode, {Locale? deviceLocale}) async {
    final fallback = _fallbackLocaleForFlavor(targetMode);
    final resolvedDeviceLocale = _normalizeDeviceLocale(
      deviceLocale,
      fallback,
      targetMode,
    );
    final locale = targetMode == AppFlavor.cn ? fallback : resolvedDeviceLocale;
    final countryCode =
        targetMode == AppFlavor.cn ? 'CN' : (locale.countryCode ?? 'US');
    final baseCurrency = _defaultCurrencyForCountry(countryCode);

    await _prefs.setString(_modeKey, targetMode.name);
    await _prefs.setBool(_modeLockedKey, true);
    await _prefs.setString(_localeKey, _toStorageLocale(locale));
    await _prefs.setString(_countryCodeKey, countryCode);
    await _prefs.setString(_baseCurrencyKey, baseCurrency);
    notifyListeners();
  }

  int get currentSchemaVersion => _prefs.getInt(_schemaVersionKey) ?? schemaVersion;

  int get currentMigrationVersion =>
      _prefs.getInt(_migrationVersionKey) ?? migrationVersion;

  AppProfile get currentProfile => AppProfile(
    flavor: flavor,
    localeProfile: _buildLocaleProfile(),
    capabilityProfile: _buildCapabilityProfile(),
  );

  String get appTitle => flavor == AppFlavor.cn ? 'AI财富账本' : 'AI Wealth Ledger';

  String get privacyPolicyUrl => flavor == AppFlavor.intl
      ? 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html'
      : 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy.html';

  String get termsOfServiceUrl => flavor == AppFlavor.intl
      ? 'https://www.apple.com/legal/internet-services/itunes/'
      : 'https://www.apple.com/legal/internet-services/itunes/cn/terms.html';

  LocaleProfile get currentLocaleProfile => currentProfile.localeProfile;

  Locale get currentLocale => currentLocaleProfile.locale;

  String get currentBaseCurrency => currentLocaleProfile.baseCurrency;

  String get speechLocaleId => _toStorageLocale(currentLocale);

  Future<void> updateLocaleProfile({
    required Locale locale,
    required String countryCode,
    required String baseCurrency,
  }) async {
    await _prefs.setString(_localeKey, _toStorageLocale(locale));
    await _prefs.setString(_countryCodeKey, countryCode.toUpperCase());
    await _prefs.setString(_baseCurrencyKey, baseCurrency.toUpperCase());
    notifyListeners();
  }

  LocaleProfile _buildLocaleProfile() {
    final fallback = _fallbackLocaleForFlavor(flavor);
    final storedLocale = _prefs.getString(_localeKey);
    final locale = storedLocale == null
        ? fallback
        : _fromStorageLocale(storedLocale, fallback);
    final countryCode = (_prefs.getString(_countryCodeKey) ??
            locale.countryCode ??
            (flavor == AppFlavor.cn ? 'CN' : 'US'))
        .toUpperCase();
    final baseCurrency =
        (_prefs.getString(_baseCurrencyKey) ?? _defaultCurrencyForCountry(countryCode))
            .toUpperCase();

    return LocaleProfile(
      locale: locale,
      countryCode: countryCode,
      baseCurrency: baseCurrency,
      dateFormat: _dateFormatForLocale(locale),
      numberFormat: '#,##0.##',
      currencyFormat: 'currency:$baseCurrency',
    );
  }

  CapabilityProfile _buildCapabilityProfile() {
    if (flavor == AppFlavor.cn) {
      return const CapabilityProfile(
        authProviders: [AuthProviderType.phoneSms],
        ocrProvider: OcrProviderType.legacyCnOcr,
        aiProvider: AiProviderType.legacyCnAi,
        stockMarketScope: StockMarketScope.cn,
        featureFlags: {
          'intlAuth': false,
          'usStock': false,
          'fxSystem': true,
          'chinaWalletAssets': true,
        },
      );
    }

    return const CapabilityProfile(
      authProviders: [
        AuthProviderType.emailOtp,
        AuthProviderType.google,
        AuthProviderType.apple,
      ],
      ocrProvider: OcrProviderType.googleVisionGemini,
      aiProvider: AiProviderType.gemini,
      stockMarketScope: StockMarketScope.us,
      featureFlags: {
        'intlAuth': true,
        'usStock': true,
        'fxSystem': true,
        'chinaWalletAssets': false,
      },
    );
  }

  Locale _fallbackLocaleForFlavor(AppFlavor flavor) {
    return flavor == AppFlavor.cn
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US');
  }

  Locale _normalizeDeviceLocale(
    Locale? deviceLocale,
    Locale fallback,
    AppFlavor flavor,
  ) {
    if (flavor == AppFlavor.cn) return const Locale('zh', 'CN');
    if (deviceLocale == null) return fallback;
    final country = (deviceLocale.countryCode ?? '').toUpperCase();
    if (deviceLocale.languageCode.toLowerCase() != 'en') {
      return fallback;
    }
    switch (country) {
      case 'GB':
        return const Locale('en', 'GB');
      case 'AU':
        return const Locale('en', 'AU');
      case 'US':
        return const Locale('en', 'US');
      default:
        return const Locale('en', 'US');
    }
  }

  AppFlavor? get _storedMode {
    final raw = _prefs.getString(_modeKey)?.trim();
    if (raw == 'cn') return AppFlavor.cn;
    if (raw == 'intl') return AppFlavor.intl;
    return null;
  }

  bool get _hasExistingSession {
    final hasLoggedIn = _prefs.getBool('has_logged_in') ?? false;
    final accountKey = _prefs.getString('logged_in_phone')?.trim() ?? '';
    final authProvider = _prefs.getString('logged_in_auth_provider')?.trim() ?? '';
    return hasLoggedIn || accountKey.isNotEmpty || authProvider.isNotEmpty;
  }

  AppFlavor _resolveEffectiveMode({
    required AppFlavor inferredMode,
    required bool sessionExists,
  }) {
    final storedMode = _storedMode;
    if (storedMode != null) return storedMode;
    return sessionExists ? _inferModeFromStoredSession(inferredMode) : inferredMode;
  }

  AppFlavor _inferMode(Locale? deviceLocale) {
    if (deviceLocale == null) return AppFlavor.intl;
    return deviceLocale.languageCode.toLowerCase().startsWith('zh')
        ? AppFlavor.cn
        : AppFlavor.intl;
  }

  AppFlavor _inferModeFromStoredSession(AppFlavor fallback) {
    final provider = (_prefs.getString('logged_in_auth_provider') ?? '').trim();
    switch (provider) {
      case 'phone':
        return AppFlavor.cn;
      case 'google':
      case 'apple':
      case 'email':
        return AppFlavor.intl;
      case 'demo':
        final email = (_prefs.getString('logged_in_email') ?? '').trim().toLowerCase();
        if (email == 'demo@aimoneyledger.app') return AppFlavor.intl;
        return AppFlavor.cn;
      case 'guest':
      default:
        return fallback;
    }
  }

  String _defaultCurrencyForCountry(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'CN':
        return 'CNY';
      case 'GB':
        return 'GBP';
      case 'AU':
        return 'AUD';
      case 'DE':
      case 'FR':
      case 'IT':
      case 'ES':
      case 'NL':
      case 'BE':
      case 'FI':
      case 'IE':
      case 'PT':
      case 'AT':
      case 'GR':
      case 'LU':
        return 'EUR';
      case 'US':
      default:
        return 'USD';
    }
  }

  String _dateFormatForLocale(Locale locale) {
    final tag = _toStorageLocale(locale);
    switch (tag) {
      case 'zh_CN':
        return 'yyyy-MM-dd';
      case 'en_GB':
        return 'dd/MM/yyyy';
      case 'en_AU':
        return 'dd/MM/yyyy';
      case 'en_US':
      default:
        return 'MM/dd/yyyy';
    }
  }

  String _toStorageLocale(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';

  Locale _fromStorageLocale(String raw, Locale fallback) {
    final parts = raw.split(RegExp('[-_]'));
    if (parts.isEmpty || parts.first.isEmpty) return fallback;
    if (parts.length == 1) return Locale(parts.first);
    return Locale(parts.first, parts[1].toUpperCase());
  }
}
