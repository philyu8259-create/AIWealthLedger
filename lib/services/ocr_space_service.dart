import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'config_service.dart';
import 'ai/receipt_ocr_service.dart';

/// OCR.space 免费 OCR 服务
/// API 文档：https://ocr.space/ocrapi
/// 免费额度：25,000 次/月
class OcrSpaceService implements ReceiptOcrService {
  Dio get _dio => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// OCR.space API Key（在 https://ocr.space/ocrapi 免费注册获取）
  String get _apiKey => ConfigService.instance.ocrSpaceApiKey;

  bool get _isConfigured => _apiKey.isNotEmpty;

  /// 识别图片文字
  /// [imageBytes] - 图片二进制数据
  /// 返回识别的纯文本
  @override
  Future<String?> recognizeText(List<int> imageBytes) async {
    if (!_isConfigured) {
      debugPrint('[OCR.space] not configured (no API key)');
      return null;
    }

    try {
      debugPrint('[OCR.space] Recognizing...');
      final base64Image = base64Encode(imageBytes);

      final resp = await _dio.post(
        'https://api.ocr.space/parse/image',
        data: {
          'base64Image': base64Image,
          'language': 'chs',
          'isOverlayRequired': false,
          'detectOrientation': true,
          'scale': true,
          'OCREngine': 2,
        },
        options: Options(
          headers: {
            'apikey': _apiKey,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          validateStatus: (status) => true,
        ),
      );

      if (resp.statusCode != 200) {
        debugPrint('[OCR.space] HTTP error: ${resp.statusCode}');
        return null;
      }

      final data = resp.data as Map<String, dynamic>;
      final errorMessage = data['ErrorMessage'] as String?;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        debugPrint('[OCR.space] API error: $errorMessage');
        return null;
      }

      final parsedResults = data['ParsedResults'] as List<dynamic>?;
      if (parsedResults == null || parsedResults.isEmpty) {
        debugPrint('[OCR.space] no results');
        return null;
      }

      final first = parsedResults.first as Map<String, dynamic>;
      final text = first['ParsedText'] as String? ?? '';

      debugPrint(
        '[OCR.space] success: ${text.substring(0, text.length.clamp(0, 80))}...',
      );
      return text.trim();
    } catch (e) {
      debugPrint('[OCR.space] error: $e');
      return null;
    }
  }

  /// 识别票据（与通用文字识别相同）
  @override
  Future<String?> recognizeReceipt(List<int> imageBytes) async {
    return recognizeText(imageBytes);
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
