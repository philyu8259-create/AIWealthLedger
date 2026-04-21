import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

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
      return const Left('通义千问 API Key 未配置');
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
        return const Left('AI 响应为空');
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) {
        return const Left('无法解析 AI 响应');
      }

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      return Right(_parsePrediction(parsed));
    } catch (e) {
      return Left('AI 预测失败: $e');
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
}
