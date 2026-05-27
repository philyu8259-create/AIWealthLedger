import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/app/profile/capability_profile.dart';
import 'package:ai_accounting_app/services/app_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppFlavor _oppositeFlavor(AppFlavor flavor) =>
    flavor == AppFlavor.cn ? AppFlavor.intl : AppFlavor.cn;

Locale _expectedLocale(AppFlavor flavor) => flavor == AppFlavor.cn
    ? const Locale('zh', 'CN')
    : const Locale('en', 'US');

String _expectedCurrency(AppFlavor flavor) =>
    flavor == AppFlavor.cn ? 'CNY' : 'USD';

String _expectedAppTitle(AppFlavor flavor) =>
    flavor == AppFlavor.cn ? '财富记账本' : 'AI Wealth Tracker';

List<AuthProviderType> _expectedAuthProviders(AppFlavor flavor) =>
    flavor == AppFlavor.cn
    ? const [AuthProviderType.phoneSms]
    : const [AuthProviderType.google, AuthProviderType.apple];

Future<AppProfileService> _loadService([
  Map<String, Object> initialValues = const {},
]) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return AppProfileService(prefs);
}

void main() {
  if (!AppFlavorX.hasExplicitBuildFlavor) {
    return;
  }

  final explicitFlavor = AppFlavorX.buildFlavor;

  group('AppProfileService explicit APP_FLAVOR pinning', () {
    test(
      'explicit CN build stays CN despite EN device + persisted intl settings',
      () async {
        final service = await _loadService({
          'app_mode': 'intl',
          'has_logged_in': true,
          'app_locale': 'en_US',
          'app_country_code': 'US',
          'app_base_currency': 'USD',
        });

        await service.ensureInitialized(deviceLocale: const Locale('en', 'US'));

        expect(service.flavor, explicitFlavor);
        expect(service.currentLocale, _expectedLocale(explicitFlavor));
        expect(service.currentBaseCurrency, _expectedCurrency(explicitFlavor));
        expect(service.appTitle, _expectedAppTitle(explicitFlavor));
        expect(
          service.currentProfile.capabilityProfile.authProviders,
          equals(_expectedAuthProviders(explicitFlavor)),
        );
        expect(service.isModeLocked, isTrue);
      },
      skip: explicitFlavor == AppFlavor.cn ? null : 'Build is INTL flavor',
    );

    test(
      'explicit INTL build stays INTL despite ZH device + persisted CN settings',
      () async {
        final service = await _loadService({
          'app_mode': 'cn',
          'has_logged_in': true,
          'app_locale': 'zh_CN',
          'app_country_code': 'CN',
          'app_base_currency': 'CNY',
        });

        await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));

        expect(service.flavor, explicitFlavor);
        expect(service.currentLocale, _expectedLocale(explicitFlavor));
        expect(service.currentBaseCurrency, _expectedCurrency(explicitFlavor));
        expect(service.appTitle, _expectedAppTitle(explicitFlavor));
        expect(
          service.currentProfile.capabilityProfile.authProviders,
          equals(_expectedAuthProviders(explicitFlavor)),
        );
        expect(service.isModeLocked, isTrue);
      },
      skip: explicitFlavor == AppFlavor.intl ? null : 'Build is CN flavor',
    );

    test('explicit build does not allow cross-flavor switchMode', () async {
      final service = await _loadService();
      final crossFlavor = _oppositeFlavor(explicitFlavor);

      await service.ensureInitialized(
        deviceLocale: _expectedLocale(explicitFlavor),
      );
      expect(service.isModeLocked, isTrue);

      await service.switchMode(crossFlavor);

      expect(service.flavor, explicitFlavor);
      expect(service.currentLocale, _expectedLocale(explicitFlavor));
      expect(service.currentBaseCurrency, _expectedCurrency(explicitFlavor));
      expect(service.isModeLocked, isTrue);
    });
  });
}
