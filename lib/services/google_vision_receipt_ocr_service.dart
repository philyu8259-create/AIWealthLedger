import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai/receipt_ocr_service.dart';
import 'config_service.dart';

class GoogleVisionReceiptOcrService implements ReceiptOcrService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  String get _apiKey => ConfigService.instance.googleVisionApiKey;
  bool get _isConfigured => ConfigService.instance.isGoogleVisionConfigured;

  @override
  Future<String?> recognizeReceipt(List<int> imageBytes) {
    return recognizeText(imageBytes);
  }

  @override
  Future<String?> recognizeText(List<int> imageBytes) async {
    if (!_isConfigured) {
      debugPrint('[GoogleVisionOCR] not configured');
      return null;
    }

    try {
      final response = await _dio.post(
        'https://vision.googleapis.com/v1/images:annotate?key=$_apiKey',
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {
          'requests': [
            {
              'image': {'content': base64Encode(imageBytes)},
              'features': [
                {'type': 'DOCUMENT_TEXT_DETECTION'},
              ],
              'imageContext': {'languageHints': _languageHints()},
            },
          ],
        },
      );

      final responses = response.data['responses'] as List<dynamic>?;
      if (responses == null || responses.isEmpty) return null;
      final first = responses.first as Map<String, dynamic>;

      final error = first['error'] as Map<String, dynamic>?;
      if (error != null) {
        debugPrint('[GoogleVisionOCR] API error: ${error['message']}');
        return null;
      }

      final fullText =
          (first['fullTextAnnotation'] as Map<String, dynamic>?)?['text']
              as String?;
      if (fullText != null && fullText.trim().isNotEmpty) {
        return fullText.trim();
      }

      final textAnnotations = first['textAnnotations'] as List<dynamic>?;
      final description = textAnnotations == null || textAnnotations.isEmpty
          ? null
          : (textAnnotations.first as Map<String, dynamic>)['description']
                as String?;
      return description?.trim();
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          '[GoogleVisionOCR] error: status=${e.response?.statusCode} data=${e.response?.data}',
        );
      } else {
        debugPrint('[GoogleVisionOCR] error: $e');
      }
      return null;
    }
  }

  List<String> _languageHints() {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = locale.languageCode.toLowerCase();
    final countryCode = (locale.countryCode ?? '').toUpperCase();
    final hints = <String>['en', languageCode];

    switch (countryCode) {
      case 'CN':
      case 'TW':
      case 'HK':
      case 'MO':
        hints.add('zh');
        break;
      case 'PH':
        hints.addAll(['fil', 'tl']);
        break;
      case 'TH':
        hints.add('th');
        break;
      case 'VN':
        hints.add('vi');
        break;
      case 'JP':
        hints.add('ja');
        break;
      case 'KR':
        hints.add('ko');
        break;
      case 'ID':
        hints.add('id');
        break;
      case 'MY':
        hints.add('ms');
        break;
      case 'TR':
        hints.add('tr');
        break;
    }

    return hints.where((hint) => hint.isNotEmpty).toSet().toList();
  }
}
