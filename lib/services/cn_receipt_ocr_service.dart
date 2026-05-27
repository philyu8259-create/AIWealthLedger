import 'package:flutter/foundation.dart';

import 'ai/receipt_ocr_service.dart';

/// CN 场景 OCR 服务聚合器
///
/// 默认链路：Baidu -> OCR.space -> Aliyun。
/// 顺序来源于既有稳定性优先级：先走 Baidu（中文适配较好），再走 OCR.space（免费/回退），
/// 最后走阿里云 OCR 兜底，任何 provider 只要返回空字符串或抛异常都会继续尝试下一个。
class CnReceiptOcrService implements ReceiptOcrService {
  CnReceiptOcrService(this._providers);

  final List<ReceiptOcrService> _providers;

  @override
  Future<String?> recognizeText(List<int> imageBytes) async {
    return _runWithFallback(
      (provider) => provider.recognizeText(imageBytes),
      'recognizeText',
    );
  }

  @override
  Future<String?> recognizeReceipt(List<int> imageBytes) async {
    return _runWithFallback(
      (provider) => provider.recognizeReceipt(imageBytes),
      'recognizeReceipt',
    );
  }

  Future<String?> _runWithFallback(
    Future<String?> Function(ReceiptOcrService provider) action,
    String methodName,
  ) async {
    for (var i = 0; i < _providers.length; i++) {
      final provider = _providers[i];
      final providerName = provider.runtimeType.toString();
      try {
        final result = await action(provider);
        final trimmed = result?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          return trimmed;
        }

        debugPrint('[CnReceiptOCR][$methodName] $providerName returned empty');
      } catch (error, stackTrace) {
        debugPrint(
          '[CnReceiptOCR][$methodName] $providerName failed: $error\\n$stackTrace',
        );
      }
    }
    return null;
  }
}
