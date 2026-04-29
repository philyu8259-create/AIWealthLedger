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
    Locale('zh', 'TW'),
    Locale('zh', 'HK'),
    Locale('zh', 'MO'),
    Locale('en', 'US'),
    Locale('en', 'GB'),
    Locale('en', 'AU'),
    Locale('en', 'CA'),
    Locale('en', 'NZ'),
    Locale('en', 'IE'),
    Locale('en', 'PH'),
    Locale('en', 'SG'),
    Locale('en', 'MY'),
    Locale('en', 'IN'),
    Locale('en', 'HK'),
    Locale('en', 'ZA'),
    Locale('en', 'AE'),
    Locale('en', 'SA'),
    Locale('ja', 'JP'),
    Locale('ko', 'KR'),
    Locale('id', 'ID'),
    Locale('th', 'TH'),
    Locale('tr', 'TR'),
    Locale('vi', 'VN'),
    Locale('de', 'DE'),
    Locale('fr', 'FR'),
    Locale('it', 'IT'),
    Locale('es', 'ES'),
    Locale('es', 'MX'),
    Locale('nl', 'NL'),
    Locale('pt', 'PT'),
    Locale('pt', 'BR'),
    Locale('pl', 'PL'),
    Locale('sv', 'SE'),
    Locale('da', 'DK'),
    Locale('nb', 'NO'),
    Locale('cs', 'CZ'),
    Locale('hu', 'HU'),
    Locale('ro', 'RO'),
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
    final shouldSeedFlavorLocale =
        previousStoredMode == null &&
        sessionExists &&
        resolvedMode != inferredMode;
    final initialLocale = shouldSeedFlavorLocale
        ? fallback
        : resolvedDeviceLocale;
    final initialCountry = _countryCodeForProfile(
      deviceLocale: shouldSeedFlavorLocale ? null : deviceLocale,
      locale: initialLocale,
      flavor: resolvedMode,
    );
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
    final locale = resolvedDeviceLocale;
    final countryCode = _countryCodeForProfile(
      deviceLocale: deviceLocale,
      locale: locale,
      flavor: targetMode,
    );
    final baseCurrency = _defaultCurrencyForCountry(countryCode);

    await _prefs.setString(_modeKey, targetMode.name);
    await _prefs.setBool(_modeLockedKey, true);
    await _prefs.setString(_localeKey, _toStorageLocale(locale));
    await _prefs.setString(_countryCodeKey, countryCode);
    await _prefs.setString(_baseCurrencyKey, baseCurrency);
    notifyListeners();
  }

  int get currentSchemaVersion =>
      _prefs.getInt(_schemaVersionKey) ?? schemaVersion;

  int get currentMigrationVersion =>
      _prefs.getInt(_migrationVersionKey) ?? migrationVersion;

  AppProfile get currentProfile => AppProfile(
    flavor: flavor,
    localeProfile: _buildLocaleProfile(),
    capabilityProfile: _buildCapabilityProfile(),
  );

  String get appTitle =>
      flavor == AppFlavor.cn ? 'AI财富记账本' : 'AI Wealth Tracker';

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
    final countryCode =
        (_prefs.getString(_countryCodeKey) ??
                locale.countryCode ??
                (flavor == AppFlavor.cn ? 'CN' : 'US'))
            .toUpperCase();
    final baseCurrency =
        (_prefs.getString(_baseCurrencyKey) ??
                _defaultCurrencyForCountry(countryCode))
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
        authProviders: [AuthProviderType.phoneSms, AuthProviderType.apple],
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
    if (deviceLocale == null) return fallback;

    final languageCode = deviceLocale.languageCode.toLowerCase();
    final country = (deviceLocale.countryCode ?? '').toUpperCase();

    if (flavor == AppFlavor.cn) {
      if (country == 'TW') return const Locale('zh', 'TW');
      if (country == 'HK') return const Locale('zh', 'HK');
      if (country == 'MO') return const Locale('zh', 'MO');
      return const Locale('zh', 'CN');
    }

    if (languageCode.startsWith('zh')) {
      if (country == 'TW') return const Locale('zh', 'TW');
      if (country == 'HK') return const Locale('zh', 'HK');
      if (country == 'MO') return const Locale('zh', 'MO');
      return const Locale('zh', 'CN');
    }

    final regionalLocale = _localeForLanguageAndCountry(languageCode, country);
    if (regionalLocale != null) {
      return regionalLocale;
    }

    if (languageCode != 'en') {
      return fallback;
    }

    switch (country) {
      case 'GB':
        return const Locale('en', 'GB');
      case 'AU':
        return const Locale('en', 'AU');
      case 'CA':
        return const Locale('en', 'CA');
      case 'NZ':
        return const Locale('en', 'NZ');
      case 'IE':
        return const Locale('en', 'IE');
      case 'PH':
        return const Locale('en', 'PH');
      case 'SG':
        return const Locale('en', 'SG');
      case 'MY':
        return const Locale('en', 'MY');
      case 'IN':
        return const Locale('en', 'IN');
      case 'HK':
        return const Locale('en', 'HK');
      case 'ZA':
        return const Locale('en', 'ZA');
      case 'AE':
        return const Locale('en', 'AE');
      case 'SA':
        return const Locale('en', 'SA');
      case 'US':
        return const Locale('en', 'US');
      default:
        return const Locale('en', 'US');
    }
  }

  Locale? _localeForLanguageAndCountry(String languageCode, String country) {
    switch ('${languageCode}_$country') {
      case 'ja_JP':
        return const Locale('ja', 'JP');
      case 'ko_KR':
        return const Locale('ko', 'KR');
      case 'id_ID':
        return const Locale('id', 'ID');
      case 'th_TH':
        return const Locale('th', 'TH');
      case 'tr_TR':
        return const Locale('tr', 'TR');
      case 'vi_VN':
        return const Locale('vi', 'VN');
      case 'de_DE':
        return const Locale('de', 'DE');
      case 'fr_FR':
        return const Locale('fr', 'FR');
      case 'it_IT':
        return const Locale('it', 'IT');
      case 'es_ES':
        return const Locale('es', 'ES');
      case 'es_MX':
        return const Locale('es', 'MX');
      case 'nl_NL':
        return const Locale('nl', 'NL');
      case 'pt_PT':
        return const Locale('pt', 'PT');
      case 'pt_BR':
        return const Locale('pt', 'BR');
      case 'pl_PL':
        return const Locale('pl', 'PL');
      case 'sv_SE':
        return const Locale('sv', 'SE');
      case 'da_DK':
        return const Locale('da', 'DK');
      case 'nb_NO':
        return const Locale('nb', 'NO');
      case 'cs_CZ':
        return const Locale('cs', 'CZ');
      case 'hu_HU':
        return const Locale('hu', 'HU');
      case 'ro_RO':
        return const Locale('ro', 'RO');
      default:
        return null;
    }
  }

  String _countryCodeForProfile({
    required Locale? deviceLocale,
    required Locale locale,
    required AppFlavor flavor,
  }) {
    final deviceCountry = (deviceLocale?.countryCode ?? '').toUpperCase();
    if (_hasCurrencyForCountry(deviceCountry)) return deviceCountry;
    return (locale.countryCode ?? (flavor == AppFlavor.cn ? 'CN' : 'US'))
        .toUpperCase();
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
    final authProvider =
        _prefs.getString('logged_in_auth_provider')?.trim() ?? '';
    return hasLoggedIn || accountKey.isNotEmpty || authProvider.isNotEmpty;
  }

  AppFlavor _resolveEffectiveMode({
    required AppFlavor inferredMode,
    required bool sessionExists,
  }) {
    final storedMode = _storedMode;
    if (storedMode != null) return storedMode;
    return sessionExists
        ? _inferModeFromStoredSession(inferredMode)
        : inferredMode;
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
        final email = (_prefs.getString('logged_in_email') ?? '')
            .trim()
            .toLowerCase();
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
      case 'TW':
        return 'TWD';
      case 'MO':
        return 'MOP';
      case 'PH':
        return 'PHP';
      case 'TR':
        return 'TRY';
      case 'SG':
        return 'SGD';
      case 'MY':
        return 'MYR';
      case 'TH':
        return 'THB';
      case 'HK':
        return 'HKD';
      case 'VN':
        return 'VND';
      case 'JP':
        return 'JPY';
      case 'KR':
        return 'KRW';
      case 'IN':
        return 'INR';
      case 'ID':
        return 'IDR';
      case 'CA':
        return 'CAD';
      case 'GB':
        return 'GBP';
      case 'AU':
        return 'AUD';
      case 'NZ':
        return 'NZD';
      case 'CH':
        return 'CHF';
      case 'SE':
        return 'SEK';
      case 'NO':
        return 'NOK';
      case 'DK':
        return 'DKK';
      case 'PL':
        return 'PLN';
      case 'CZ':
        return 'CZK';
      case 'HU':
        return 'HUF';
      case 'RO':
        return 'RON';
      case 'BR':
        return 'BRL';
      case 'MX':
        return 'MXN';
      case 'ZA':
        return 'ZAR';
      case 'AE':
        return 'AED';
      case 'SA':
        return 'SAR';
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
      case 'EE':
      case 'LV':
      case 'LT':
      case 'SI':
      case 'SK':
      case 'MT':
      case 'CY':
        return 'EUR';
      case 'US':
      default:
        return 'USD';
    }
  }

  bool _hasCurrencyForCountry(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'CN':
      case 'TW':
      case 'MO':
      case 'PH':
      case 'TR':
      case 'SG':
      case 'MY':
      case 'TH':
      case 'HK':
      case 'VN':
      case 'JP':
      case 'KR':
      case 'IN':
      case 'ID':
      case 'CA':
      case 'GB':
      case 'AU':
      case 'NZ':
      case 'CH':
      case 'SE':
      case 'NO':
      case 'DK':
      case 'PL':
      case 'CZ':
      case 'HU':
      case 'RO':
      case 'BR':
      case 'MX':
      case 'ZA':
      case 'AE':
      case 'SA':
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
      case 'EE':
      case 'LV':
      case 'LT':
      case 'SI':
      case 'SK':
      case 'MT':
      case 'CY':
      case 'US':
        return true;
      default:
        return false;
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
