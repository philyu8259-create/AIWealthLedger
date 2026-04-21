import 'dart:io';

import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:ai_accounting_app/services/gemini_input_parser_service.dart';
import 'package:ai_accounting_app/services/gemini_spending_prediction_service.dart';
import 'package:ai_accounting_app/services/google_vision_receipt_ocr_service.dart';

Future<void> main() async {
  await ConfigService.instance.load();

  final parser = GeminiInputParserService();
  final parsed = await parser.parseInput('coffee 4.5');
  stdout.writeln('parsed=$parsed');

  final predictor = GeminiSpendingPredictionService();
  final now = DateTime.now();
  final prediction = await predictor.predictSpending(
    entries: [
      AccountEntry(
        id: '1',
        amount: 22,
        type: EntryType.expense,
        category: 'food',
        description: 'lunch',
        date: DateTime(now.year, now.month - 2, 5),
        createdAt: now,
      ),
      AccountEntry(
        id: '2',
        amount: 18,
        type: EntryType.expense,
        category: 'coffee',
        description: 'latte',
        date: DateTime(now.year, now.month - 1, 8),
        createdAt: now,
      ),
      AccountEntry(
        id: '3',
        amount: 35,
        type: EntryType.expense,
        category: 'transport',
        description: 'uber',
        date: DateTime(now.year, now.month, 3),
        createdAt: now,
      ),
    ],
    currentMonthExpense: 35,
  );
  stdout.writeln('prediction=$prediction');

  final ocr = GoogleVisionReceiptOcrService();
  final file = File('tmp/qa/intl-home-round1.png');
  final text = await ocr.recognizeText(await file.readAsBytes());
  final preview = text?.substring(0, text.length > 200 ? 200 : text.length);
  stdout.writeln('ocr=$preview');
}
