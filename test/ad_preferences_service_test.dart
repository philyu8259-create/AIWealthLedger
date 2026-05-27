import 'package:ai_accounting_app/services/ad_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personalized ads default on and can be disabled', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = AdPreferencesService(prefs);

    expect(service.personalizedAdsEnabled, isTrue);

    await service.setPersonalizedAdsEnabled(false);

    expect(service.personalizedAdsEnabled, isFalse);
  });

  test('ads are blocked before consent and for active members', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = AdPreferencesService(prefs);

    expect(
      service.shouldRequestAds(hasPrivacyConsent: false, isVip: false),
      isFalse,
    );
    expect(
      service.shouldRequestAds(hasPrivacyConsent: true, isVip: true),
      isFalse,
    );
    expect(
      service.shouldRequestAds(hasPrivacyConsent: true, isVip: false),
      isTrue,
    );
  });
}
