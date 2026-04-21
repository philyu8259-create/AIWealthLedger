import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../features/accounting/domain/entities/entities.dart';
import '../features/accounting/domain/usecases/predict_spending.dart';
import 'config_service.dart';

class GeminiSpendingPredictionService implements SpendingPredictionService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  String get _apiKey => ConfigService.instance.geminiApiKey;
  bool get _isConfigured => ConfigService.instance.isGeminiConfigured;

  static const String _systemPrompt = '''You are a personal finance analyst.
Based on the user's historical expenses, return valid JSON only with:
1. predictedTotalExpense
2. predictedDailyAverage
3. categoryPredictions
4. budgetRecommendations
5. warnings
6. aiInsight''';

  @override
  Future<Either<String, SpendingPrediction>> predictSpending({
    required List<AccountEntry> entries,
    required double currentMonthExpense,
  }) async {
    if (!_isConfigured) {
      return const Left('Gemini API key is not configured');
    }

    final prompt = _buildPrompt(_buildHistorySummary(entries), currentMonthExpense);

    try {
      final response = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {
          'systemInstruction': {
            'parts': [
              {'text': _systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.2,
            'responseMimeType': 'application/json',
            'maxOutputTokens': 512,
            'thinkingConfig': {'thinkingBudget': 0},
          },
        },
      );

      final content = _extractText(response.data);
      if (content.isEmpty) {
        return const Left('Gemini response is empty');
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) {
        return const Left('Failed to parse Gemini response');
      }

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      return Right(_parsePrediction(parsed));
    } catch (e) {
      if (e is DioException) {
        // 运行时保留详细日志便于排查，但前台返回保持简洁，避免把底层异常直接甩给用户。
        debugPrint(
          '[GeminiPrediction] error type=${e.type} message=${e.message} status=${e.response?.statusCode} data=${e.response?.data} error=${e.error}',
        );
        return Left(
          'Failed to generate prediction, please retry.',
        );
      }
      return Left('Gemini prediction failed: $e');
    }
  }

  String _extractText(dynamic data) {
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return '';
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return '';
    return (parts.first['text'] as String? ?? '').trim();
  }

  String _buildHistorySummary(List<AccountEntry> entries) {
    final monthMap = <String, Map<String, double>>{};
    for (final e in entries.where((e) => e.type == EntryType.expense)) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      monthMap.putIfAbsent(key, () => {});
      monthMap[key]![e.category] = (monthMap[key]![e.category] ?? 0) + e.amount;
    }

    final buffer = StringBuffer();
    for (final entry in monthMap.entries) {
      buffer.writeln('Month: ${entry.key}');
      double monthTotal = 0;
      for (final cat in entry.value.entries) {
        final catDef = CategoryDef.findById(cat.key);
        buffer.writeln('  ${catDef?.name ?? cat.key}: ${cat.value.toStringAsFixed(0)}');
        monthTotal += cat.value;
      }
      buffer.writeln('  Total expense: ${monthTotal.toStringAsFixed(0)}');
    }
    return buffer.toString();
  }

  String _buildPrompt(String history, double currentMonthExpense) {
    return '''Based on the following recent monthly expense history, and current month recorded expense ${currentMonthExpense.toStringAsFixed(0)}, return JSON in this format:
{
  "predictedTotalExpense": 3500.0,
  "predictedDailyAverage": 116.0,
  "categoryPredictions": {"food": 1200.0, "transport": 300.0},
  "budgetRecommendations": {"food": 1500.0, "transport": 400.0},
  "warnings": ["Food spending is close to budget"],
  "aiInsight": "A one sentence insight"
}

History:
$history''';
  }

  SpendingPrediction _parsePrediction(Map<String, dynamic> json) {
    final catPreds = <String, double>{};
    final catRaw = json['categoryPredictions'] as Map<String, dynamic>?;
    catRaw?.forEach((k, v) => catPreds[k] = (v as num).toDouble());

    final budgetRecs = <String, double>{};
    final budgetRaw = json['budgetRecommendations'] as Map<String, dynamic>?;
    budgetRaw?.forEach((k, v) => budgetRecs[k] = (v as num).toDouble());

    final warnings = (json['warnings'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return SpendingPrediction(
      predictedTotalExpense: (json['predictedTotalExpense'] as num?)?.toDouble() ?? 0,
      predictedDailyAverage: (json['predictedDailyAverage'] as num?)?.toDouble() ?? 0,
      categoryPredictions: catPreds,
      budgetRecommendations: budgetRecs,
      warnings: warnings,
      aiInsight: (json['aiInsight'] as String? ?? '').trim(),
    );
  }
}
