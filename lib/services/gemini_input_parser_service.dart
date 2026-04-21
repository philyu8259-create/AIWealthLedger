import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai/input_parser_service.dart';
import 'config_service.dart';

class GeminiInputParserService implements InputParserService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String get _apiKey => ConfigService.instance.geminiApiKey;
  bool get _isConfigured => ConfigService.instance.isGeminiConfigured;

  static const String _systemPrompt = '''You are an accounting parser for a personal finance app.
Extract transactions from natural language and return valid JSON only.

Expense categories: food, transport, shopping, entertainment, housing, health, education, beauty, social, travel, sports, coffee, snack, fruit, daily, other
Income categories: salary, bonus, investment, gift, refund, other_income

Rules:
- Support multiple transactions in one sentence.
- type=income only for salary, income, bonus, gift, refund, reimbursement and similar income wording.
- Use category ids above.
- Keep note concise.
- Output JSON only.

Format:
{
  "transactions": [
    {"amount": 12.5, "category": "coffee", "note": "latte", "type": "expense"}
  ]
}''';

  @override
  Future<List<ParsedResult>> parseInput(String input) async {
    if (!_isConfigured) return _fallbackParse(input);

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
                {'text': input},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.2,
            'responseMimeType': 'application/json',
            'maxOutputTokens': 256,
            'thinkingConfig': {'thinkingBudget': 0},
          },
        },
      );

      final content = _extractText(response.data);
      if (content.isEmpty) return _fallbackParse(input);

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) return _fallbackParse(input);

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final txns = (parsed['transactions'] as List?) ?? [];

      return txns
          .map(
            (t) => ParsedResult(
              amount: (t['amount'] as num?)?.toDouble() ?? 0,
              category: (t['category'] as String? ?? 'other').trim(),
              note: (t['note'] as String? ?? '').trim(),
              type: (t['type'] as String?) == 'income' ? 'income' : 'expense',
            ),
          )
          .where((t) => t.amount > 0)
          .toList();
    } catch (e) {
      debugPrint('[GeminiInputParser] parseInput error: $e');
      return _fallbackParse(input);
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

  List<ParsedResult> _fallbackParse(String input) {
    final results = <ParsedResult>[];
    for (final match in RegExp(r'(\S+?)(\d+(?:\.\d{1,2})?)').allMatches(input)) {
      final note = match.group(1)?.trim() ?? '';
      final amount = double.tryParse(match.group(2) ?? '') ?? 0;
      if (amount > 0 && amount < 1000000) {
        results.add(
          ParsedResult(
            amount: amount,
            category: _guessCategory('$note $input'),
            note: note.isEmpty
                ? input.substring(0, input.length.clamp(0, 30))
                : note,
            type: RegExp(
              r'salary|income|bonus|gift|refund|reimbursement|工资|收入|奖金|红包|退款|报销',
              caseSensitive: false,
            ).hasMatch(input)
                ? 'income'
                : 'expense',
          ),
        );
      }
    }
    return results;
  }

  String _guessCategory(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'breakfast|lunch|dinner|hotpot|takeout|meal|restaurant|coffee|milk tea|早餐|午饭|晚饭|火锅|外卖|咖啡|奶茶|吃饭').hasMatch(t)) {
      return t.contains('coffee') || t.contains('咖啡') ? 'coffee' : 'food';
    }
    if (RegExp(r'taxi|uber|metro|subway|bus|train|flight|打车|地铁|公交').hasMatch(t)) {
      return 'transport';
    }
    if (RegExp(r'shopping|amazon|taobao|jd|mall|购物|淘宝|京东').hasMatch(t)) {
      return 'shopping';
    }
    if (RegExp(r'movie|game|karaoke|netflix|电影|游戏|唱歌').hasMatch(t)) {
      return 'entertainment';
    }
    if (RegExp(r'rent|utility|mortgage|房租|水电|物业').hasMatch(t)) {
      return 'housing';
    }
    if (RegExp(r'hospital|doctor|medicine|pharmacy|医院|药店|医疗').hasMatch(t)) {
      return 'health';
    }
    if (RegExp(r'salary|income|bonus|工资|收入|奖金').hasMatch(t)) {
      return 'salary';
    }
    return 'other';
  }
}
