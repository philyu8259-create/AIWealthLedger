import 'package:ai_accounting_app/services/ai_privacy_consent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app privacy consent starts false and can be recorded', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = AIPrivacyConsentService(prefs);

    expect(service.hasAppPrivacyConsent, isFalse);

    await service.setAppPrivacyConsent();

    expect(service.hasAppPrivacyConsent, isTrue);
  });

  test('clearAll removes app and AI feature consent values', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = AIPrivacyConsentService(prefs);

    await service.setAppPrivacyConsent();
    await service.setOcrConsent();
    await service.setVoiceConsent();
    await service.setTextConsent();

    await service.clearAll();

    expect(service.hasAppPrivacyConsent, isFalse);
    expect(service.hasOcrConsent, isFalse);
    expect(service.hasVoiceConsent, isFalse);
    expect(service.hasTextConsent, isFalse);
  });
}
