import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/app/profile/capability_profile.dart';
import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';
import 'package:ai_accounting_app/services/app_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppProfileService> createProfileService() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return AppProfileService(prefs);
  }

  test(
    'Chinese mode uses A-share scope and international mode uses US scope',
    () async {
      final service = await createProfileService();

      await service.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));
      expect(
        service.currentProfile.capabilityProfile.stockMarketScope,
        StockMarketScope.cn,
      );

      await service.switchMode(
        AppFlavor.intl,
        deviceLocale: const Locale('en', 'US'),
      );
      expect(
        service.currentProfile.capabilityProfile.stockMarketScope,
        StockMarketScope.us,
      );
    },
  );

  test(
    'stock provider unavailable copy separates A-share and US stock providers',
    () {
      final zh = AppStrings.forLocale(const Locale('zh'));
      final en = AppStrings.forLocale(const Locale('en'));

      expect(
        zh.text(AppStringKeys.assetsCnStockProviderPendingTitle),
        contains('A 股'),
      );
      expect(
        zh.text(AppStringKeys.assetsCnStockProviderPendingContent),
        contains('智兔 A 股'),
      );
      expect(
        zh.text(AppStringKeys.assetsCnStockProviderPendingContent),
        isNot(contains('美股')),
      );
      expect(
        zh.text(AppStringKeys.assetsStockProviderPendingTitle),
        contains('美股'),
      );
      expect(
        en.text(AppStringKeys.assetsStockProviderPendingTitle),
        contains('US stock'),
      );
      expect(
        en.text(AppStringKeys.assetsCnStockProviderPendingTitle),
        contains('A-share'),
      );
    },
  );
}
