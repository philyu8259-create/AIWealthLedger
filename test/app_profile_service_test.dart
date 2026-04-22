import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/services/app_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppProfileService', () {
    Future<AppProfileService> createService([
      Map<String, Object> initialValues = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initialValues);
      final prefs = await SharedPreferences.getInstance();
      return AppProfileService(prefs);
    }

    test('first launch uses zh system locale to seed CN mode', () async {
      final service = await createService();

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));

      expect(service.flavor, AppFlavor.cn);
      expect(service.currentLocale, const Locale('zh', 'CN'));
      expect(service.currentBaseCurrency, 'CNY');
      expect(service.isModeLocked, false);
    });

    test('first resolved mode stays stable before login and does not auto-jump', () async {
      final service = await createService();

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));
      expect(service.flavor, AppFlavor.cn);

      await service.ensureInitialized(deviceLocale: const Locale('en', 'US'));

      expect(service.flavor, AppFlavor.cn);
      expect(service.currentLocale, const Locale('zh', 'CN'));
      expect(service.currentBaseCurrency, 'CNY');
    });

    test('existing intl session without stored mode is inferred and locked', () async {
      final service = await createService({
        'has_logged_in': true,
        'logged_in_auth_provider': 'google',
        'logged_in_phone': 'google:demo',
      });

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));

      expect(service.flavor, AppFlavor.intl);
      expect(service.currentLocale, const Locale('en', 'US'));
      expect(service.currentBaseCurrency, 'USD');
      expect(service.isModeLocked, true);
    });

    test('existing cn session without stored mode is inferred and locked', () async {
      final service = await createService({
        'has_logged_in': true,
        'logged_in_auth_provider': 'phone',
        'logged_in_phone': '13800138000',
      });

      await service.ensureInitialized(deviceLocale: const Locale('en', 'US'));

      expect(service.flavor, AppFlavor.cn);
      expect(service.currentLocale, const Locale('zh', 'CN'));
      expect(service.currentBaseCurrency, 'CNY');
      expect(service.isModeLocked, true);
    });

    test('explicit switch mode updates locale, currency, and lock state', () async {
      final service = await createService();

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));
      await service.switchMode(
        AppFlavor.intl,
        deviceLocale: const Locale('en', 'GB'),
      );

      expect(service.flavor, AppFlavor.intl);
      expect(service.currentLocale, const Locale('en', 'GB'));
      expect(service.currentBaseCurrency, 'GBP');
      expect(service.isModeLocked, true);
    });
  });
}
