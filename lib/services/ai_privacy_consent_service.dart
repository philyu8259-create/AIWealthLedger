import 'package:shared_preferences/shared_preferences.dart';

class AIPrivacyConsentService {
  static const _ocrConsentKey = 'ai_ocr_consent';
  static const _voiceConsentKey = 'ai_voice_consent';
  static const _textConsentKey = 'ai_text_consent';

  final SharedPreferences _prefs;

  AIPrivacyConsentService(this._prefs);

  /// 检查 OCR 授权状态
  bool get hasOcrConsent => _prefs.getBool(_ocrConsentKey) == true;

  /// 检查语音授权状态
  bool get hasVoiceConsent => _prefs.getBool(_voiceConsentKey) == true;

  /// 检查文本输入授权状态
  bool get hasTextConsent => _prefs.getBool(_textConsentKey) == true;

  /// 记录 OCR 授权
  Future<void> setOcrConsent() async {
    await _prefs.setBool(_ocrConsentKey, true);
  }

  /// 记录语音授权
  Future<void> setVoiceConsent() async {
    await _prefs.setBool(_voiceConsentKey, true);
  }

  /// 记录文本输入授权
  Future<void> setTextConsent() async {
    await _prefs.setBool(_textConsentKey, true);
  }

  /// 清除所有授权（注销时调用）
  Future<void> clearAll() async {
    await _prefs.remove(_ocrConsentKey);
    await _prefs.remove(_voiceConsentKey);
    await _prefs.remove(_textConsentKey);
  }
}
