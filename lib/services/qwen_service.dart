import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'config_service.dart';
import 'ai/input_parser_service.dart';

/// 通义千问（QWEN）语义解析服务
class QwenService implements InputParserService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String get _apiKey => ConfigService.instance.qwenApiKey;
  bool get _isConfigured => ConfigService.instance.isQwenConfigured;

  static const String _systemPrompt = '''你是一个专业的AI记账助手。解析用户输入，提取金额、类目、备注。

【类目ExpenseID】：food餐饮🍜 transport交通🚗 shopping购物🛒 entertainment娱乐🎮
housing居住🏠 health医疗💊 education教育📚 beauty美容💅 social社交👥
travel旅行✈️ sports运动⚽ coffee咖啡☕ snack零食🍬 fruit水果🍎 daily日用品🧴 other其他📦

【类目IncomeID】：salary工资💰 bonus奖金🎁 investment投资收益📈 gift红包🧧 refund退款↩️ other_income其他

【金额识别规则 - 重要！同一笔交易只取一个金额】
1. 电商订单/物流/购物小票场景：
   - 看到"实付"、"券后"、"已付"、"支付"、"成交价"、"到手价" → 以这个金额为准
   - 看到"原价"、"标价"、"定价"、"价格"、"¥xx"（单独出现，非实付）→ **忽略，不是实际支出**
   - **严禁**把原价和实付金额识别为两笔独立的账单！
2. 超市/餐厅/普通小票：识别每行商品的金额
3. 无论哪种场景，每笔真实交易只输出一个金额

【规则】
- 支持多笔记账："早餐15，午饭40，打车30" → 3条账单
- type=income 仅当包含"工资|收入|奖金|红包|退款|报销"
- 输出JSON格式，禁止其他内容

【输出格式】
{
  "transactions": [
    {"amount": 120, "category": "food", "note": "火锅", "type": "expense"}
  ]
}''';

  @override
  Future<List<ParsedResult>> parseInput(String input) async {
    if (!_isConfigured) return _fallbackParse(input);

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
            {'role': 'user', 'content': input},
          ],
          'temperature': 0.3,
        },
      );

      final content =
          (response.data['choices']?[0]?['message']?['content'] as String?)
              ?.trim() ??
          '';

      if (content.isEmpty) return _fallbackParse(input);

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) return _fallbackParse(input);

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final txns = (parsed['transactions'] as List?) ?? [];

      return txns
          .map((t) {
            final type = (t['type'] as String?) == 'income'
                ? 'income'
                : 'expense';
            return ParsedResult(
              amount: (t['amount'] as num?)?.toDouble() ?? 0,
              category: t['category'] as String? ?? 'other',
              note: (t['note'] as String?) ?? '',
              type: type,
            );
          })
          .where((t) => t.amount > 0)
          .toList();
    } catch (e) {
      debugPrint('[Qwen] parseInput error: $e');
      return _fallbackParse(input);
    }
  }

  List<ParsedResult> _fallbackParse(String input) {
    final results = <ParsedResult>[];
    for (final match in RegExp(
      r'(\S+?)(\d+(?:\.\d{1,2})?)',
    ).allMatches(input)) {
      final note = match.group(1)?.trim() ?? '';
      final amount = double.tryParse(match.group(2) ?? '') ?? 0;
      if (amount > 0 && amount < 1000000) {
        results.add(
          ParsedResult(
            amount: amount,
            category: _guessCategory(note + input),
            note: note.isEmpty
                ? input.substring(0, input.length.clamp(0, 20))
                : note,
            type: RegExp(r'工资|收入|奖金|红包|退款|报销').hasMatch(input)
                ? 'income'
                : 'expense',
          ),
        );
      }
    }
    if (results.isEmpty) {
      final spent = RegExp(r'花了[^\d]*(\d+(?:\.\d{1,2})?)').firstMatch(input);
      if (spent != null) {
        results.add(
          ParsedResult(
            amount: double.parse(spent.group(1)!),
            category: _guessCategory(input),
            note: input.substring(0, input.length.clamp(0, 30)),
            type: 'expense',
          ),
        );
      }
    }
    return results;
  }

  String _guessCategory(String text) {
    final t = text.toLowerCase();
    if (t.contains('早餐') ||
        t.contains('午饭') ||
        t.contains('晚饭') ||
        t.contains('火锅') ||
        t.contains('外卖') ||
        t.contains('咖啡') ||
        t.contains('奶茶') ||
        t.contains('吃饭')) {
      return 'food';
    }
    if (t.contains('打车') || t.contains('地铁') || t.contains('公交')) {
      return 'transport';
    }
    if (t.contains('购物') || t.contains('淘宝') || t.contains('京东')) {
      return 'shopping';
    }
    if (t.contains('电影') || t.contains('游戏') || t.contains('唱歌')) {
      return 'entertainment';
    }
    if (t.contains('房租') || t.contains('水电') || t.contains('物业')) {
      return 'housing';
    }
    if (t.contains('医院') || t.contains('药店') || t.contains('医疗')) {
      return 'health';
    }
    if (t.contains('工资') || t.contains('收入') || t.contains('奖金')) {
      return 'salary';
    }
    return 'other';
  }
}
