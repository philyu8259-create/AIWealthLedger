import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'config_service.dart';

/// 阿里云 ASR（语音识别）服务
class AliyunASRService {
  final Dio _dio = Dio();
  String? _cachedToken;
  DateTime? _cachedTokenExpiry;

  String get _accessKeyId => ConfigService.instance.aliyunAccessKeyId;
  String get _accessKeySecret => ConfigService.instance.aliyunAccessKeySecret;
  String get _appKey => ConfigService.instance.aliyunAsrAppKey;
  bool get _isConfigured =>
      ConfigService.instance.isAliyunConfigured && _appKey.isNotEmpty;

  static const _tokenHost = 'nls-meta.cn-shanghai.aliyuncs.com';
  static const _asrUrl =
      'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr';
  static const _signatureMethod = 'HMAC-SHA1';
  static const _signatureVersion = '1.0';
  static const _tokenVersion = '2019-02-28';
  static const _nlsRegion = 'cn-shanghai';
  static const _tokenRefreshBuffer = Duration(minutes: 1);

  String _currentUtcTimestamp() {
    final t = DateTime.now().toUtc();
    return '${t.year.toString().padLeft(4, '0')}-${_p2(t.month)}-${_p2(t.day)}T'
        '${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}Z';
  }

  static String _p2(int v) => v.toString().padLeft(2, '0');

  bool get _tokenAlive {
    final expiry = _cachedTokenExpiry;
    if (expiry == null) return _cachedToken != null;
    return DateTime.now().toUtc().isBefore(
      expiry.subtract(_tokenRefreshBuffer),
    );
  }

  Future<String?> _getToken() async {
    if (_cachedToken != null && _tokenAlive) return _cachedToken;
    if (!_isConfigured) return null;
    _cachedToken = null;
    _cachedTokenExpiry = null;

    try {
      final params = <String, String>{
        'AccessKeyId': _accessKeyId,
        'Action': 'CreateToken',
        'Format': 'JSON',
        'RegionId': _nlsRegion,
        'SignatureMethod': _signatureMethod,
        'SignatureNonce': const Uuid().v4(),
        'SignatureVersion': _signatureVersion,
        'Timestamp': _currentUtcTimestamp(),
        'Version': _tokenVersion,
      };
      params['Signature'] = _makeSignature(
        params,
        'GET',
        '/',
        _accessKeySecret,
      );

      final response = await _dio.get(
        'https://$_tokenHost',
        queryParameters: params,
        options: Options(validateStatus: (status) => true),
      );

      final data = _normalizeMap(response.data);
      if (response.statusCode != 200) {
        debugPrint('[ASR] getToken http status=${response.statusCode}');
        return null;
      }
      var token = _coalesceString(data, const ['Id', 'Token', 'AccessToken']);
      var expireValue =
          data['ExpireTime'] ?? data['Expire'] ?? data['Expire-In'];
      final tokenSection = _asStringKeyMap(data['Token']);
      if (token == null && tokenSection != null) {
        token = _coalesceString(tokenSection, const [
          'Id',
          'Token',
          'AccessToken',
        ]);
        expireValue ??=
            tokenSection['ExpireTime'] ??
            tokenSection['Expire'] ??
            tokenSection['Expire-In'];
      }
      final dataSection = data['Data'];
      if (token == null && dataSection is Map<String, dynamic>) {
        token = _coalesceString(dataSection, const [
          'Id',
          'Token',
          'AccessToken',
        ]);
        final nestedTokenSection = _asStringKeyMap(dataSection['Token']);
        if (token == null && nestedTokenSection != null) {
          token = _coalesceString(nestedTokenSection, const [
            'Id',
            'Token',
            'AccessToken',
          ]);
          expireValue ??=
              nestedTokenSection['ExpireTime'] ??
              nestedTokenSection['Expire'] ??
              nestedTokenSection['Expire-In'];
        }
        // Keep this explicit: the analyzer's ??= suggestion is awkward here
        // because the fallback spans several Aliyun response shapes.
        // ignore: prefer_conditional_assignment
        if (expireValue == null) {
          expireValue =
              dataSection['ExpireTime'] ??
              dataSection['Expire'] ??
              dataSection['Expire-In'];
        }
      }
      if (token == null || token.isEmpty) {
        debugPrint('[ASR] getToken response missing token keys=${data.keys}');
        return null;
      }
      final expire = _parseExpires(expireValue);

      _cachedToken = token;
      _cachedTokenExpiry =
          expire ?? DateTime.now().toUtc().add(const Duration(hours: 1));
      return _cachedToken;
    } catch (e) {
      debugPrint('[ASR] getToken error: $e');
      return null;
    }
  }

  /// 短语音识别（音频 bytes → 文字）
  Future<String?> recognizeBytes(List<int> audioBytes) async {
    if (!_isConfigured) return null;
    if (audioBytes.isEmpty) return null;

    try {
      final token = await _getToken();
      if (token == null) return null;

      final queryParameters = <String, String>{
        'appkey': _appKey,
        'format': 'pcm',
        'sample_rate': '16000',
        'enable_punctuation_prediction': 'true',
        'enable_inverse_text_normalization': 'true',
      };
      final response = await _dio.post(
        _asrUrl,
        queryParameters: queryParameters,
        data: audioBytes,
        options: Options(
          headers: {
            'X-NLS-Token': token,
            'Content-Type': 'application/octet-stream',
          },
          sendTimeout: const Duration(seconds: 65),
          receiveTimeout: const Duration(seconds: 65),
          validateStatus: (status) => true,
        ),
      );

      final responseData = _normalizeMap(response.data);
      if (response.statusCode != 200) {
        debugPrint('[ASR] recognize http status=${response.statusCode}');
        return null;
      }
      final status = responseData['status'] ?? responseData['Status'];
      final message = responseData['message'] ?? responseData['Message'] ?? '';
      if (status != null && status != 20000000 && status != '20000000') {
        debugPrint('[ASR] recognize api status=$status message=$message');
        return null;
      }
      final text = _extractAsrText(responseData);
      debugPrint('[ASR] recognize textLength=${text?.length ?? 0}');
      return text;
    } catch (e) {
      debugPrint('[ASR] recognizeBytes error: $e');
      return null;
    }
  }

  String _makeSignature(
    Map<String, String> params,
    String method,
    String path,
    String secret,
  ) {
    final sorted = Map<String, String>.from(params)..remove('Signature');
    final keys = sorted.keys.toList()..sort();
    final sb = StringBuffer();
    for (int i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (i > 0) sb.write('&');
      sb.write(_percentEncode(k));
      sb.write('=');
      sb.write(_percentEncode(sorted[k]!));
    }
    final stringToSign =
        '${_percentEncode(method)}&${_percentEncode(path)}&${_percentEncode(sb.toString())}';

    final hmac = Hmac(sha1, utf8.encode('$secret&'));
    final digest = hmac.convert(utf8.encode(stringToSign));
    return base64Encode(digest.bytes);
  }

  String _percentEncode(String value) {
    return Uri.encodeComponent(
      value,
    ).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');
  }

  Map<String, dynamic> _normalizeMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) return parsed;
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  String? _coalesceString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  DateTime? _parseExpires(dynamic value) {
    if (value == null) return null;
    if (value is int) return _parseEpochSecondsOrMilliseconds(value);
    if (value is num) return _parseEpochSecondsOrMilliseconds(value.toInt());
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed.toUtc();
      final seconds = int.tryParse(trimmed);
      if (seconds != null) return _parseEpochSecondsOrMilliseconds(seconds);
    }
    return null;
  }

  DateTime _parseEpochSecondsOrMilliseconds(int value) {
    if (value > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  String? _extractAsrText(Map<String, dynamic> response) {
    final directText = _coalesceString(response, const [
      'text',
      'Text',
      'result',
    ]);
    if (directText != null && directText.isNotEmpty) return directText;

    final result = response['result'];
    if (result is Map<String, dynamic>) {
      final text = _coalesceString(result, const ['text', 'Text', 'sentence']);
      if (text != null && text.isNotEmpty) return text;
    }
    final payload = response['payload'];
    if (payload is Map<String, dynamic>) {
      final payloadResult = payload['result'];
      if (payloadResult is String && payloadResult.isNotEmpty) {
        return payloadResult;
      }
      if (payloadResult is Map<String, dynamic>) {
        final text = _coalesceString(payloadResult, const ['text', 'Text']);
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return null;
  }
}
