import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/services/pangle_ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PangleAdService', () {
    test('shows home banner only for consented free users on CN Android', () {
      const service = PangleAdService();

      expect(
        service.shouldShowHomeBanner(
          flavor: AppFlavor.cn,
          platform: TargetPlatform.android,
          hasPrivacyConsent: true,
          isVip: false,
        ),
        isTrue,
      );

      expect(
        service.shouldShowHomeBanner(
          flavor: AppFlavor.cn,
          platform: TargetPlatform.android,
          hasPrivacyConsent: false,
          isVip: false,
        ),
        isFalse,
      );
      expect(
        service.shouldShowHomeBanner(
          flavor: AppFlavor.cn,
          platform: TargetPlatform.android,
          hasPrivacyConsent: true,
          isVip: true,
        ),
        isFalse,
      );
      expect(
        service.shouldShowHomeBanner(
          flavor: AppFlavor.intl,
          platform: TargetPlatform.android,
          hasPrivacyConsent: true,
          isVip: false,
        ),
        isFalse,
      );
      expect(
        service.shouldShowHomeBanner(
          flavor: AppFlavor.cn,
          platform: TargetPlatform.iOS,
          hasPrivacyConsent: true,
          isVip: false,
        ),
        isFalse,
      );
    });

    test('uses the created Pangle media and banner slot IDs', () {
      const config = PangleAdConfig.homeBanner;

      expect(config.appId, '5827353');
      expect(config.codeId, '104073039');
      expect(config.widthDp, 300);
      expect(config.heightDp, 150);
    });
  });
}
