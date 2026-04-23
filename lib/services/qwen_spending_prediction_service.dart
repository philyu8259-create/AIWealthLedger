import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../features/accounting/domain/entities/entities.dart';
import '../features/accounting/domain/usecases/predict_spending.dart';
import 'config_service.dart';

class QwenSpendingPredictionService implements SpendingPredictionService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  String get _apiKey => ConfigService.instance.qwenApiKey;
  bool get _isConfigured => ConfigService.instance.isQwenConfigured;

  static const String _systemPrompt = '''你是一个专业的个人理财分析师。
根据用户的历史账单数据，分析消费习惯，给出：
1. 本月总支出预测
2. 各类目金额预测
3. 下月预算建议（合理、克制但可执行）
4. 超支预警（如果某类目接近或超过预算的80%）
5. 一句话总结洞察

回复必须是有效JSON，禁止其他内容。''';

  @override
  Future<Either<String, SpendingPrediction>> predictSpending({
    required List<AccountEntry> entries,
    required double currentMonthExpense,
  }) async {
    if (!_isConfigured) {
      debugPrint(
        '[QwenSpendingPredictionService] QWEN_API_KEY missing, using local fallback prediction.',
      );
      return Right(
        _buildLocalFallbackPrediction(
          entries: entries,
          currentMonthExpense: currentMonthExpense,
        ),
      );
    }

    final summary = _buildHistorySummary(entries);
    final prompt = _buildPrompt(summary, currentMonthExpense);

    try {
      final response = await _dio.post(
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': 'qwen-turbo',
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.3,
        },
      );

      final content =
          (response.data['choices']?[0]?['message']?['content'] as String?)
              ?.trim() ??
          '';

      if (content.isEmpty) {
        return Right(
          _buildLocalFallbackPrediction(
            entries: entries,
            currentMonthExpense: currentMonthExpense,
          ),
        );
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) {
        return Right(
          _buildLocalFallbackPrediction(
            entries: entries,
            currentMonthExpense: currentMonthExpense,
          ),
        );
      }

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      return Right(_parsePrediction(parsed));
    } catch (e) {
      debugPrint(
        '[QwenSpendingPredictionService] Qwen request failed, falling back locally: $e',
      );
      return Right(
        _buildLocalFallbackPrediction(
          entries: entries,
          currentMonthExpense: currentMonthExpense,
        ),
      );
    }
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
      buffer.writeln('月份: ${entry.key}');
      double monthTotal = 0;
      for (final cat in entry.value.entries) {
        final catDef = CategoryDef.findById(cat.key);
        buffer.writeln(
          '  ${catDef?.name ?? cat.key}: ¥${cat.value.toStringAsFixed(0)}',
        );
        monthTotal += cat.value;
      }
      buffer.writeln('  当月总支出: ¥${monthTotal.toStringAsFixed(0)}');
    }
    return buffer.toString();
  }

  String _buildPrompt(String history, double currentMonthExpense) {
    return '''
基于以下近3个月历史账单数据，结合当月已记账 ¥${currentMonthExpense.toStringAsFixed(0)}，给出：

1. 预测本月总支出
2. 预测各类目金额
3. 下月各类目预算建议（每人）
4. 超支预警（如有）
5. 一句总结性洞察

历史账单：
$history

请用JSON返回，格式如下：
{
  "predictedTotalExpense": 3500.0,
  "predictedDailyAverage": 116.0,
  "categoryPredictions": {"food": 1200.0, "transport": 300.0},
  "budgetRecommendations": {"food": 1500.0, "transport": 400.0},
  "warnings": ["餐饮支出已达预算80%，注意控制"],
  "aiInsight": "本月支出较上月同期增长10%，建议减少外出就餐"
}
''';
  }

  SpendingPrediction _parsePrediction(Map<String, dynamic> json) {
    final catPreds = <String, double>{};
    final catRaw = json['categoryPredictions'] as Map<String, dynamic>?;
    catRaw?.forEach((k, v) => catPreds[k] = (v as num).toDouble());

    final budgetRecs = <String, double>{};
    final budgetRaw = json['budgetRecommendations'] as Map<String, dynamic>?;
    budgetRaw?.forEach((k, v) => budgetRecs[k] = (v as num).toDouble());

    final warnings = (json['warnings'] as List?)?.cast<String>() ?? [];

    return SpendingPrediction(
      predictedTotalExpense:
          (json['predictedTotalExpense'] as num?)?.toDouble() ?? 0,
      predictedDailyAverage:
          (json['predictedDailyAverage'] as num?)?.toDouble() ?? 0,
      categoryPredictions: catPreds,
      budgetRecommendations: budgetRecs,
      warnings: warnings,
      aiInsight: json['aiInsight'] as String? ?? '',
    );
  }

  SpendingPrediction _buildLocalFallbackPrediction({
    required List<AccountEntry> entries,
    required double currentMonthExpense,
  }) {
    final expenseEntries = entries.where((e) => e.type == EntryType.expense).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final monthlyTotals = <String, double>{};
    final monthlyCategoryTotals = <String, Map<String, double>>{};

    for (final entry in expenseEntries) {
      final monthKey =
          '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
      monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + entry.amount;
      monthlyCategoryTotals.putIfAbsent(monthKey, () => <String, double>{});
      monthlyCategoryTotals[monthKey]![entry.category] =
          (monthlyCategoryTotals[monthKey]![entry.category] ?? 0) + entry.amount;
    }

    final monthCount = monthlyTotals.isEmpty ? 1 : monthlyTotals.length;
    final averageMonthlyExpense =
        monthlyTotals.values.fold<double>(0, (sum, value) => sum + value) /
        monthCount;

    final now = DateTime.now();
    final daysPassed = now.day.clamp(1, 31);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final paceProjection = currentMonthExpense <= 0
        ? averageMonthlyExpense
        : (currentMonthExpense / daysPassed) * daysInMonth;

    final predictedTotalExpense = [
      currentMonthExpense,
      averageMonthlyExpense * 0.42 + paceProjection * 0.58,
    ].reduce((a, b) => a > b ? a : b);

    final predictedDailyAverage = daysInMonth == 0
        ? predictedTotalExpense
        : predictedTotalExpense / daysInMonth;

    final averageCategoryTotals = <String, double>{};
    for (final categoryMap in monthlyCategoryTotals.values) {
      for (final item in categoryMap.entries) {
        averageCategoryTotals[item.key] =
            (averageCategoryTotals[item.key] ?? 0) + item.value;
      }
    }
    averageCategoryTotals.updateAll(
      (key, value) => value / monthCount,
    );

    final currentMonthEntries = expenseEntries
        .where(
          (entry) => entry.date.year == now.year && entry.date.month == now.month,
        )
        .toList();
    final currentMonthCategories = <String, double>{};
    for (final entry in currentMonthEntries) {
      currentMonthCategories[entry.category] =
          (currentMonthCategories[entry.category] ?? 0) + entry.amount;
    }

    final categoryPredictions = <String, double>{};
    final budgetRecommendations = <String, double>{};
    final categoryKeys = {
      ...averageCategoryTotals.keys,
      ...currentMonthCategories.keys,
    };

    for (final key in categoryKeys) {
      final averageValue = averageCategoryTotals[key] ?? 0;
      final currentValue = currentMonthCategories[key] ?? 0;
      final projectedCurrent = currentValue <= 0
          ? averageValue
          : (currentValue / daysPassed) * daysInMonth;
      final predictedValue = averageValue == 0
          ? projectedCurrent
          : averageValue * 0.45 + projectedCurrent * 0.55;
      categoryPredictions[key] = predictedValue;
      budgetRecommendations[key] = predictedValue * 0.92;
    }

    final warnings = <String>[];
    final sortedCurrentCategories = currentMonthCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final item in sortedCurrentCategories.take(2)) {
      final predictedValue = categoryPredictions[item.key] ?? 0;
      if (predictedValue <= 0) continue;
      final usageRate = item.value / predictedValue;
      if (usageRate >= 0.78) {
        final categoryName = CategoryDef.findById(item.key)?.name ?? item.key;
        warnings.add('$categoryName 本月支出已接近预测上限，建议后续几天适当放缓。');
      }
    }

    final topCategory = categoryPredictions.entries.isEmpty
        ? null
        : (categoryPredictions.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first;
    final topCategoryName = topCategory == null
        ? '日常开销'
        : (CategoryDef.findById(topCategory.key)?.name ?? topCategory.key);
    final trendDelta = predictedTotalExpense - averageMonthlyExpense;
    final trendText = trendDelta >= 0 ? '略高于' : '低于';

    return SpendingPrediction(
      predictedTotalExpense: predictedTotalExpense,
      predictedDailyAverage: predictedDailyAverage,
      categoryPredictions: categoryPredictions,
      budgetRecommendations: budgetRecommendations,
      warnings: warnings,
      aiInsight:
          '当前构建未连接通义千问，已使用本地账单趋势生成预测。本月支出预计$trendText近几个月均值，$topCategoryName 仍是最值得优先关注的类目。',
    );
  }
}
