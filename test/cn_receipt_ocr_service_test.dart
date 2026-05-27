import 'package:ai_accounting_app/services/ai/receipt_ocr_service.dart';
import 'package:ai_accounting_app/services/cn_receipt_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageBytes = <int>[1, 2, 3, 4];

  group('CnReceiptOcrService', () {
    test(
      'recognizeText uses Baidu first and does not call fallback on success',
      () async {
        final baidu = _StubReceiptOcrService(textOutcomes: ['  baidu text  ']);
        final ocrSpace = _StubReceiptOcrService(
          textOutcomes: ['ocrspace text'],
        );
        final aliyun = _StubReceiptOcrService(textOutcomes: ['aliyun text']);
        final service = CnReceiptOcrService([baidu, ocrSpace, aliyun]);

        final result = await service.recognizeText(imageBytes);

        expect(result, 'baidu text');
        expect(baidu.textCalls, equals(1));
        expect(ocrSpace.textCalls, equals(0));
        expect(aliyun.textCalls, equals(0));
      },
    );

    test('recognizeText falls back to OCR.space when Baidu is empty', () async {
      final baidu = _StubReceiptOcrService(textOutcomes: ['   ']);
      final ocrSpace = _StubReceiptOcrService(textOutcomes: ['ocrspace text']);
      final aliyun = _StubReceiptOcrService(textOutcomes: ['aliyun text']);
      final service = CnReceiptOcrService([baidu, ocrSpace, aliyun]);

      final result = await service.recognizeText(imageBytes);

      expect(result, 'ocrspace text');
      expect(baidu.textCalls, equals(1));
      expect(ocrSpace.textCalls, equals(1));
      expect(aliyun.textCalls, equals(0));
    });

    test(
      'recognizeText falls back to OCR.space when Baidu throws exception',
      () async {
        final baidu = _StubReceiptOcrService(
          textOutcomes: [Exception('network down')],
        );
        final ocrSpace = _StubReceiptOcrService(
          textOutcomes: ['ocrspace text'],
        );
        final aliyun = _StubReceiptOcrService(textOutcomes: ['aliyun text']);
        final service = CnReceiptOcrService([baidu, ocrSpace, aliyun]);

        final result = await service.recognizeText(imageBytes);

        expect(result, 'ocrspace text');
        expect(baidu.textCalls, equals(1));
        expect(ocrSpace.textCalls, equals(1));
        expect(aliyun.textCalls, equals(0));
      },
    );

    test(
      'recognizeReceipt falls back to Aliyun when Baidu and OCR.space fail',
      () async {
        final baidu = _StubReceiptOcrService(
          receiptOutcomes: [Exception('offline')],
        );
        final ocrSpace = _StubReceiptOcrService(receiptOutcomes: [null]);
        final aliyun = _StubReceiptOcrService(
          receiptOutcomes: ['aliyun receipt'],
        );
        final service = CnReceiptOcrService([baidu, ocrSpace, aliyun]);

        final result = await service.recognizeReceipt(imageBytes);

        expect(result, 'aliyun receipt');
        expect(baidu.receiptCalls, equals(1));
        expect(ocrSpace.receiptCalls, equals(1));
        expect(aliyun.receiptCalls, equals(1));
      },
    );

    test('all providers fail then return null for both APIs', () async {
      final baidu = _StubReceiptOcrService(
        textOutcomes: [null],
        receiptOutcomes: [null],
      );
      final ocrSpace = _StubReceiptOcrService(
        textOutcomes: [''],
        receiptOutcomes: [''],
      );
      final aliyun = _StubReceiptOcrService(
        textOutcomes: [Exception('fail')],
        receiptOutcomes: [Exception('fail')],
      );
      final service = CnReceiptOcrService([baidu, ocrSpace, aliyun]);

      final textResult = await service.recognizeText(imageBytes);
      final receiptResult = await service.recognizeReceipt(imageBytes);

      expect(textResult, isNull);
      expect(receiptResult, isNull);
      expect(baidu.textCalls, equals(1));
      expect(ocrSpace.textCalls, equals(1));
      expect(aliyun.textCalls, equals(1));
      expect(baidu.receiptCalls, equals(1));
      expect(ocrSpace.receiptCalls, equals(1));
      expect(aliyun.receiptCalls, equals(1));
    });
  });
}

class _StubReceiptOcrService implements ReceiptOcrService {
  _StubReceiptOcrService({
    this.textOutcomes = const [],
    this.receiptOutcomes = const [],
  });

  final List<Object?> textOutcomes;
  final List<Object?> receiptOutcomes;

  int textCalls = 0;
  int receiptCalls = 0;

  @override
  Future<String?> recognizeText(List<int> imageBytes) async {
    return _nextOutcome(outcomes: textOutcomes, callIndex: textCalls++);
  }

  @override
  Future<String?> recognizeReceipt(List<int> imageBytes) async {
    return _nextOutcome(outcomes: receiptOutcomes, callIndex: receiptCalls++);
  }

  Future<String?> _nextOutcome({
    required List<Object?> outcomes,
    required int callIndex,
  }) async {
    if (callIndex >= outcomes.length) return null;

    final item = outcomes[callIndex];
    if (item is Exception) {
      throw item;
    }
    if (item is Error) {
      throw item;
    }

    return item as String?;
  }
}
