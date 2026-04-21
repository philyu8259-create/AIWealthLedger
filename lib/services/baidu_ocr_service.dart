import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'config_service.dart';
import 'ai/receipt_ocr_service.dart';

/// 百度 OCR 服务
/// 文档：https://cloud.baidu.com/doc/OCR/s/e1f6j6c6u
///
/// 流程：1) 获取 AccessToken 2) 用 Token 调用 OCR API
/// Token 有 30 天有效期，会自动缓存复用
class BaiduOCRService implements ReceiptOcrService {
  Dio get _dio => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String get _ak => ConfigService.instance.baiduAk;

  String get _sk => ConfigService.instance.baiduSk;

  bool get _isConfigured => _ak.isNotEmpty && _sk.isNotEmpty;

  // Token 缓存
  String? _cachedToken;
  DateTime? _tokenExpiry;

  Future<String?> _getAccessToken() async {
    if (!_isConfigured) return null;

    // 检查缓存
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }

    try {
      // URL encode parameters
      final params = {
        'grant_type': 'client_credentials',
        'client_id': _ak,
        'client_secret': _sk,
      };
      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final resp = await _dio.post(
        'https://aip.baidubce.com/oauth/2.0/token?$queryString',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => true,
        ),
      );

      if (resp.statusCode != 200) {
        debugPrint('[BaiduOCR] token request failed: ${resp.statusCode}');
        return null;
      }

      final data = resp.data as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      final expiresIn = data['expires_in'] as int?;

      if (token == null) {
        debugPrint('[BaiduOCR] no access_token in response: $data');
        return null;
      }

      // 缓存，提前 1 小时过期
      _cachedToken = token;
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: (expiresIn ?? 2592000) - 3600),
      );

      debugPrint('[BaiduOCR] token refreshed, expires in ${expiresIn}s');
      return token;
    } catch (e) {
      debugPrint('[BaiduOCR] token error: $e');
      return null;
    }
  }

  /// 通用文字识别
  @override
  Future<String?> recognizeText(List<int> imageBytes) async {
    if (!_isConfigured) {
      debugPrint('[BaiduOCR] not configured');
      return null;
    }

    try {
      debugPrint('[BaiduOCR] Recognizing...');
      final token = await _getAccessToken();
      if (token == null) {
        debugPrint('[BaiduOCR] no access token');
        return null;
      }

      final base64Image = base64Encode(imageBytes);

      final resp = await _dio.post(
        'https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token=$token',
        data: {
          'image': base64Image,
          'language_type': 'CHN_ENG', // 中英文混合
          'detect_direction': 'true',
          'paragraph': 'false',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          validateStatus: (status) => true,
        ),
      );

      if (resp.statusCode != 200) {
        debugPrint('[BaiduOCR] OCR request failed: ${resp.statusCode}');
        return null;
      }

      final data = resp.data as Map<String, dynamic>;
      final errorCode = data['error_code'];
      if (errorCode != null) {
        debugPrint('[BaiduOCR] API error: $errorCode ${data['error_msg']}');
        return null;
      }

      final wordsResult = data['words_result'] as List<dynamic>?;
      if (wordsResult == null || wordsResult.isEmpty) {
        debugPrint('[BaiduOCR] no words_result');
        return null;
      }

      final allText = wordsResult
          .map((r) => (r as Map<String, dynamic>)['words'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .join('\n');

      if (allText.isEmpty) {
        return null;
      }

      debugPrint(
        '[BaiduOCR] success: ${allText.substring(0, allText.length.clamp(0, 80))}...',
      );
      return allText;
    } catch (e) {
      debugPrint('[BaiduOCR] error: $e');
      return null;
    }
  }

  /// 票据识别（通用票据）
  @override
  Future<String?> recognizeReceipt(List<int> imageBytes) async {
    if (!_isConfigured) {
      debugPrint('[BaiduOCR] not configured');
      return null;
    }

    try {
      debugPrint('[BaiduOCR] Recognizing receipt...');
      final token = await _getAccessToken();
      if (token == null) return null;

      final base64Image = base64Encode(imageBytes);

      // 通用票据识别
      final resp = await _dio.post(
        'https://aip.baidubce.com/rest/2.0/ocr/v1/receipt?access_token=$token',
        data: {'image': base64Image},
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          validateStatus: (status) => true,
        ),
      );

      if (resp.statusCode != 200) {
        debugPrint('[BaiduOCR] receipt failed: ${resp.statusCode}');
        return null;
      }

      final data = resp.data as Map<String, dynamic>;
      final errorCode = data['error_code'];
      if (errorCode != null) {
        debugPrint('[BaiduOCR] receipt API error: $errorCode ${data['error_msg']}');
        return null;
      }

      // 票据返回的是结构化数组
      final result = data['words_result'] as Map<String, dynamic>?;
      if (result == null) {
        // 尝试通用文字识别
        return recognizeText(imageBytes);
      }

      final lines = result.entries
          .map((e) => '${e.key}: ${e.value['words'] ?? ''}')
          .join('\n');

      debugPrint('[BaiduOCR] receipt success');
      return lines;
    } catch (e) {
      debugPrint('[BaiduOCR] receipt error: $e');
      return null;
    }
  }

  /// 从识别文字中提取金额
  double? extractAmount(String ocrText) {
    for (final pattern in [
      RegExp(r'消费\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'合计[：:]\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'实付[：:]\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'总计[：:]\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'金额[：:]\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'(\d+(?:\.\d{1,2}))\s*[元块圆]'),
      RegExp(r'\b(\d+\.\d{2})\b'),
    ]) {
      final match = pattern.firstMatch(ocrText);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value > 0 && value < 1000000) return value;
      }
    }
    return null;
  }

  /// 从识别文字中提取商家名称
  String? extractMerchant(String ocrText) {
    for (final pattern in [
      RegExp(r'商家[：:]\s*(.+)'),
      RegExp(r'商户[：:]\s*(.+)'),
      RegExp(r'门店[：:]\s*(.+)'),
      RegExp(r'店名[：:]\s*(.+)'),
    ]) {
      final match = pattern.firstMatch(ocrText);
      if (match != null) return match.group(1)?.trim();
    }
    final lines = ocrText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return lines.isNotEmpty ? lines.first.trim() : null;
  }

  /// 从识别文字中提取日期
  DateTime? extractDate(String ocrText) {
    for (final pattern in [
      RegExp(r'(\d{4})[年/\-](\d{1,2})[月/\-](\d{1,2})'),
      RegExp(r'(\d{2})[年/\-](\d{1,2})[月/\-](\d{1,2})'),
    ]) {
      final match = pattern.firstMatch(ocrText);
      if (match != null) {
        int year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    }
    return null;
  }
}
