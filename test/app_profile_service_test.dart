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

    test(
      'first resolved mode stays stable before login and does not auto-jump',
      () async {
        final service = await createService();

        await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));
        expect(service.flavor, AppFlavor.cn);

        await service.ensureInitialized(deviceLocale: const Locale('en', 'US'));

        expect(service.flavor, AppFlavor.cn);
        expect(service.currentLocale, const Locale('zh', 'CN'));
        expect(service.currentBaseCurrency, 'CNY');
      },
    );

    test(
      'existing intl session without stored mode does not override app flavor',
      () async {
        final service = await createService({
          'has_logged_in': true,
          'logged_in_auth_provider': 'google',
          'logged_in_phone': 'google:demo',
        });

        await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));

        expect(service.flavor, AppFlavor.cn);
        expect(service.currentLocale, const Locale('zh', 'CN'));
        expect(service.currentBaseCurrency, 'CNY');
        expect(service.isModeLocked, true);
      },
    );

    test(
      'existing cn session without stored mode is inferred and locked',
      () async {
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
      },
    );

    test('cn app only exposes Chinese supported locales', () async {
      final service = await createService();

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));

      expect(
        service.supportedLocales,
        everyElement(
          isA<Locale>().having(
            (locale) => locale.languageCode,
            'language',
            'zh',
          ),
        ),
      );
    });

    test(
      'explicit switch mode updates locale, currency, and lock state',
      () async {
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
      },
    );

    test(
      'intl mode uses local currencies for supported Asia markets',
      () async {
        const cases = <({Locale locale, String currency})>[
          (locale: Locale('zh', 'TW'), currency: 'TWD'),
          (locale: Locale('zh', 'MO'), currency: 'MOP'),
          (locale: Locale('en', 'PH'), currency: 'PHP'),
          (locale: Locale('tr', 'TR'), currency: 'TRY'),
          (locale: Locale('en', 'SG'), currency: 'SGD'),
          (locale: Locale('en', 'MY'), currency: 'MYR'),
          (locale: Locale('th', 'TH'), currency: 'THB'),
          (locale: Locale('zh', 'HK'), currency: 'HKD'),
          (locale: Locale('vi', 'VN'), currency: 'VND'),
        ];

        for (final testCase in cases) {
          final service = await createService();

          await service.ensureInitialized(deviceLocale: testCase.locale);
          if (service.flavor == AppFlavor.cn) {
            await service.switchMode(
              AppFlavor.intl,
              deviceLocale: testCase.locale,
            );
          }

          expect(
            service.currentBaseCurrency,
            testCase.currency,
            reason: '${testCase.locale} should use ${testCase.currency}',
          );
        }
      },
    );

    test('intl mode uses local currencies for major markets', () async {
      const cases = <({Locale locale, String currency})>[
        (locale: Locale('en', 'CA'), currency: 'CAD'),
        (locale: Locale('en', 'NZ'), currency: 'NZD'),
        (locale: Locale('ja', 'JP'), currency: 'JPY'),
        (locale: Locale('ko', 'KR'), currency: 'KRW'),
        (locale: Locale('en', 'IN'), currency: 'INR'),
        (locale: Locale('id', 'ID'), currency: 'IDR'),
        (locale: Locale('de', 'DE'), currency: 'EUR'),
        (locale: Locale('fr', 'FR'), currency: 'EUR'),
        (locale: Locale('de', 'CH'), currency: 'CHF'),
        (locale: Locale('sv', 'SE'), currency: 'SEK'),
        (locale: Locale('nb', 'NO'), currency: 'NOK'),
        (locale: Locale('da', 'DK'), currency: 'DKK'),
        (locale: Locale('pl', 'PL'), currency: 'PLN'),
        (locale: Locale('cs', 'CZ'), currency: 'CZK'),
        (locale: Locale('hu', 'HU'), currency: 'HUF'),
        (locale: Locale('ro', 'RO'), currency: 'RON'),
        (locale: Locale('pt', 'BR'), currency: 'BRL'),
        (locale: Locale('es', 'MX'), currency: 'MXN'),
        (locale: Locale('en', 'ZA'), currency: 'ZAR'),
        (locale: Locale('en', 'AE'), currency: 'AED'),
        (locale: Locale('en', 'SA'), currency: 'SAR'),
      ];

      for (final testCase in cases) {
        final service = await createService();

        await service.ensureInitialized(deviceLocale: testCase.locale);
        if (service.flavor == AppFlavor.cn) {
          await service.switchMode(
            AppFlavor.intl,
            deviceLocale: testCase.locale,
          );
        }

        expect(service.flavor, AppFlavor.intl);
        expect(
          service.currentBaseCurrency,
          testCase.currency,
          reason: '${testCase.locale} should use ${testCase.currency}',
        );
      }
    });

    test('zh locales keep Chinese mode but use regional currencies', () async {
      const cases = <({Locale locale, String currency})>[
        (locale: Locale('zh', 'TW'), currency: 'TWD'),
        (locale: Locale('zh', 'HK'), currency: 'HKD'),
        (locale: Locale('zh', 'MO'), currency: 'MOP'),
        (locale: Locale('zh', 'PH'), currency: 'PHP'),
        (locale: Locale('zh', 'SG'), currency: 'SGD'),
        (locale: Locale('zh', 'MY'), currency: 'MYR'),
        (locale: Locale('zh', 'TH'), currency: 'THB'),
        (locale: Locale('zh', 'VN'), currency: 'VND'),
        (locale: Locale('zh', 'JP'), currency: 'JPY'),
        (locale: Locale('zh', 'KR'), currency: 'KRW'),
      ];

      for (final testCase in cases) {
        final service = await createService();

        await service.ensureInitialized(deviceLocale: testCase.locale);

        expect(service.flavor, AppFlavor.cn);
        expect(service.currentLocale.languageCode, 'zh');
        expect(
          service.currentBaseCurrency,
          testCase.currency,
          reason:
              '${testCase.locale} should keep Chinese UI with ${testCase.currency}',
        );
      }
    });
  });
}
