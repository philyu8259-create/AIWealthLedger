import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'config_service.dart';

/// 阿里云通用 OCR 服务
/// 使用阿里云 OCR API RecognizeAllText 接口
/// 文档：https://help.aliyun.com/zh/ocr/developer-reference/api-ocr-api-2021-07-07-recognizealltext
class AliyunOCRService {
  Dio get _dio => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// API 端点
  static const _host = 'ocrapi.cn-shanghai.aliyuncs.com';
  static const _path = '/';

  String get _keyId => ConfigService.instance.aliyunAccessKeyId;
  String get _keySecret => ConfigService.instance.aliyunAccessKeySecret;

  bool get _isConfigured => _keyId.isNotEmpty && _keySecret.isNotEmpty;

  /// V3 签名
  String _signV3(String content) {
    final key = '$_keySecret&';
    final hmac = Hmac(sha1, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(content));
    return base64Encode(digest.bytes);
  }

  /// 通用文字识别
  Future<String?> recognizeText(List<int> imageBytes) async {
    if (!_isConfigured) {
      debugPrint('[OCR] not configured');
      return null;
    }

    try {
      debugPrint('[OCR] Recognizing with Aliyun OCR...');
      final base64Image = base64Encode(imageBytes);

      // 构建请求体（JSON 格式）
      final body = {
        'body': base64Image,
        'Type': 'Advanced', // 通用文字识别高精版
      };
      final bodyJson = jsonEncode(body);
      final bodyBytes = utf8.encode(bodyJson);

      // 日期（UTC RFC 7231 格式）
      final now = DateTime.now().toUtc();
      final dateStr = _formatDate(now);

      // Content-MD5
      final contentMd5 = base64Encode(md5.convert(bodyBytes).bytes);

      // V3 签名字符串
      // StringToSign = "POST\n${Content-MD5}\n${Content-Type}\n${Date}\n${CanonicalizedResource}"
      final stringToSign =
          'POST\n$contentMd5\napplication/json\n$dateStr\n$_path';
      final signature = _signV3(stringToSign);

      final resp = await _dio.post(
        'https://$_host$_path',
        data: bodyBytes,
        options: Options(
          headers: {
            'Authorization': '$_keyId:$signature',
            'Content-Type': 'application/json',
            'Content-MD5': contentMd5,
            'Date': dateStr,
            'X-OriginalHeaders':
                'x-acs-signature-method:HMAC-SHA1\nx-acs-signature-version:1.0',
          },
          validateStatus: (status) => true,
        ),
      );

      debugPrint('[OCR] response status: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        debugPrint('[OCR] HTTP error: ${resp.statusCode}, data: ${resp.data}');
        return null;
      }

      final data = resp.data as Map<String, dynamic>?;
      if (data == null) {
        debugPrint('[OCR] null response');
        return null;
      }

      // 检查 API 错误
      final code = data['Code'] ?? data['code'] ?? data['StatusCode'];
      final message = data['Message'] ?? data['message'] ?? '';
      if (code != null && code != 200 && code != 'Success' && code != 'OK') {
        debugPrint('[OCR] API error code=$code message=$message');
        return null;
      }

      // 解析结果
      final parsedResults = data['ParsedResults'] as List<dynamic>?;
      if (parsedResults == null || parsedResults.isEmpty) {
        // 尝试其他响应格式
        final dataField = data['data'];
        if (dataField is Map) {
          final content = dataField['content'] ?? dataField['Content'] ?? '';
          if (content is String && content.isNotEmpty) {
            debugPrint(
              '[OCR] success: ${content.substring(0, content.length.clamp(0, 80))}...',
            );
            return content;
          }
        }
        debugPrint('[OCR] no parsed results');
        return null;
      }

      final allTexts = parsedResults
          .map(
            (r) => (r as Map<String, dynamic>)['ParsedText'] as String? ?? '',
          )
          .where((t) => t.isNotEmpty)
          .join('\n');

      if (allTexts.isEmpty) {
        debugPrint('[OCR] empty parsed text');
        return null;
      }

      debugPrint(
        '[OCR] success: ${allTexts.substring(0, allTexts.length.clamp(0, 80))}...',
      );
      return allTexts;
    } catch (e) {
      debugPrint('[OCR] error: $e');
      return null;
    }
  }

  /// 票据识别
  Future<String?> recognizeReceipt(List<int> imageBytes) async {
    return recognizeText(imageBytes);
  }

  String _formatDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${dt.day.toString().padLeft(2, '0')} '
        '${months[dt.month - 1]} ${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')} GMT';
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
