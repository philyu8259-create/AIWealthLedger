import 'dart:io';

import 'package:ai_accounting_app/services/baidu_ocr_service.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:ai_accounting_app/services/gemini_input_parser_service.dart';
import 'package:ai_accounting_app/services/google_vision_receipt_ocr_service.dart';
import 'package:ai_accounting_app/services/qwen_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final runLive = Platform.environment['RUN_LIVE_OCR'] == '1';

  group(
    'live receipt OCR chain',
    skip: runLive ? false : 'RUN_LIVE_OCR != 1',
    () {
      test(
        'CN OCR plus Qwen parses multi-order travel screenshot',
        () async {
          await ConfigService.instance.load();

          final imagePath = Platform.environment['CN_RECEIPT_IMAGE'];
          expect(imagePath, isNotNull);
          final bytes = await File(imagePath!).readAsBytes();

          final ocrText = await BaiduOCRService().recognizeText(bytes);
          expect(ocrText, isNotNull);
          expect(ocrText!.trim(), isNotEmpty);

          final parsed = await QwenService().parseInput(ocrText);
          expect(parsed.map((e) => e.amount), contains(2341.52));
          expect(parsed.map((e) => e.amount), contains(2652.00));
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );

      test(
        'EN OCR plus Gemini parses itemized shopping receipt',
        () async {
          await ConfigService.instance.load();

          final imagePath = Platform.environment['EN_RECEIPT_IMAGE'];
          expect(imagePath, isNotNull);
          final bytes = await File(imagePath!).readAsBytes();

          final ocrText = await GoogleVisionReceiptOcrService()
              .recognizeReceipt(bytes);
          expect(ocrText, isNotNull);
          expect(ocrText!.trim(), isNotEmpty);

          final parsed = await GeminiInputParserService().parseInput(ocrText);
          expect(parsed.length, greaterThanOrEqualTo(3));
          expect(parsed.map((e) => e.amount), containsAll([2.50, 3.00, 4.00]));
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    },
  );
}
