import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdPreferencesService extends ChangeNotifier {
  AdPreferencesService(this._prefs);

  static const _personalizedAdsEnabledKey = 'personalized_ads_enabled_v1';

  final SharedPreferences _prefs;

  bool get personalizedAdsEnabled =>
      _prefs.getBool(_personalizedAdsEnabledKey) ?? true;

  bool shouldRequestAds({
    required bool hasPrivacyConsent,
    required bool isVip,
  }) {
    return hasPrivacyConsent && !isVip;
  }

  Future<void> setPersonalizedAdsEnabled(bool enabled) async {
    await _prefs.setBool(_personalizedAdsEnabledKey, enabled);
    notifyListeners();
  }
}
