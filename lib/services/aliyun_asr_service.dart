import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'config_service.dart';

/// 阿里云 ASR（语音识别）服务
class AliyunASRService {
  final Dio _dio = Dio();
  String? _cachedToken;

  String get _accessKeyId => ConfigService.instance.aliyunAccessKeyId;
  String get _accessKeySecret => ConfigService.instance.aliyunAccessKeySecret;
  String get _appKey => ConfigService.instance.aliyunAsrAppKey;
  bool get _isConfigured => ConfigService.instance.isAliyunConfigured;

  Future<String?> _getToken() async {
    if (_cachedToken != null) return _cachedToken;
    if (!_isConfigured) return null;

    try {
      final response = await _dio.post(
        'https://nls-shanghai.aliyuncs.com/core/oauth2/token',
        data: {
          'AccessKeyId': _accessKeyId,
          'AccessKeySecret': _accessKeySecret,
          'ClientId': 'ai-accounting-flutter',
          'ResponseType': 'device_code',
          'Scope': 'audio:all',
        },
      );
      final data = response.data as Map<String, dynamic>;
      _cachedToken = data['AccessToken'] as String?;
      return _cachedToken;
    } catch (e) {
      debugPrint('[ASR] getToken error: $e');
      return null;
    }
  }

  /// 短语音识别（音频 bytes → 文字）
  Future<String?> recognizeBytes(List<int> audioBytes) async {
    if (!_isConfigured) return null;

    try {
      final token = await _getToken();
      if (token == null) return null;

      final response = await _dio.post(
        'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr',
        options: Options(
          headers: {'X-NLS-Token': token, 'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 65),
          receiveTimeout: const Duration(seconds: 65),
        ),
        data: {
          'appkey': _appKey,
          'format': 'pcm',
          'sampleRate': 16000,
          'enablePunctuationPrediction': true,
          'enableInverseTextNormalization': true,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return data['result']?['text'] as String?;
    } catch (e) {
      debugPrint('[ASR] recognizeBytes error: $e');
      return null;
    }
  }
}
