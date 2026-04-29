import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai_usage_logger.dart';
import 'ai/input_parser_service.dart';
import 'config_service.dart';

class GeminiInputParserService implements InputParserService {
  GeminiInputParserService({Dio? dio, bool? forceConfiguredForTesting})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ),
      _forceConfiguredForTesting = forceConfiguredForTesting;

  final Dio _dio;
  final bool? _forceConfiguredForTesting;

  String get _apiKey => ConfigService.instance.geminiApiKey;
  bool get _isConfigured =>
      _forceConfiguredForTesting ?? ConfigService.instance.isGeminiConfigured;

  static const String _systemPrompt =
      '''You are an accounting parser for a personal finance app.
Extract transactions from natural language and return valid JSON only.

Expense categories: food, transport, shopping, entertainment, housing, health, education, beauty, social, travel, sports, coffee, snack, fruit, daily, other
Income categories: salary, bonus, investment, gift, refund, other_income

Rules:
- Support multiple transactions in one sentence.
- type=income only for salary, income, bonus, gift, refund, reimbursement and similar income wording.
- Use category ids above.
- Keep note concise.
- Receipt/OCR/order text rule: choose the correct granularity from the document type.
- Retail/grocery/restaurant receipts with an item table should return one expense per purchased item when item names and item prices are visible.
- Travel booking, hotel booking, ticket/order cards, ecommerce orders, payment confirmations, or screenshots that show separate confirmed purchases should return one expense per confirmed purchase/order, not per metadata line.
- For receipts/orders, use the actual paid/final amount. Prefer labels such as TOTAL, GRAND TOTAL, AMOUNT DUE, BALANCE DUE, PAID, PAYMENT, SALE, NET AMOUNT, TOTAL CHARGE, CARD SALE, CASH PAID, TOTAL PAID.
- Ignore subtotal, tax, VAT/GST, discount, coupon, service charge, tip suggestions, change, cash tendered, balance, card number, authorization code, order number, invoice number, terminal ID, dates and times.
- For ecommerce/receipt text with original price and paid price, output only the paid/final amount.
- If a retail receipt contains a clear item table, output item rows and ignore subtotal/tax/total summary rows.
- Do not invent income from receipts. Refund/reimbursement text can be income only when it clearly says refund/reimbursement received.
- Use the merchant/store/ride/hotel/restaurant name as note when visible; otherwise use a short meaningful description.
- Output JSON only.

Format:
{
  "transactions": [
    {"amount": 12.5, "category": "coffee", "note": "latte", "type": "expense"}
  ]
}''';

  @override
  Future<List<ParsedResult>> parseInput(String input) async {
    final localDecision = _localParseDecision(input);
    if (localDecision.shouldSkipModel) {
      debugPrint(
        '[GeminiInputParser] local parse hit confidence=${localDecision.confidence.toStringAsFixed(2)} reason=${localDecision.reason}',
      );
      return localDecision.results;
    }
    if (!_isConfigured) return localDecision.results;

    final inputTokenEstimate =
        AiUsageLogger.estimateTokens(_systemPrompt) +
        AiUsageLogger.estimateTokens(input);

    try {
      final response = await _dio.post(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$_apiKey',
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
            'maxOutputTokens': 512,
            'thinkingConfig': {'thinkingBudget': 0},
          },
        },
      );

      final content = _extractText(response.data);
      if (content.isEmpty) {
        AiUsageLogger.logGemini(
          feature: 'entry_parse',
          model: 'gemini-2.5-flash-lite',
          cacheHit: false,
          inputTokens: inputTokenEstimate,
          outputTokens: 0,
          status: 'empty',
        );
        return _fallbackParse(input);
      }
      AiUsageLogger.logGemini(
        feature: 'entry_parse',
        model: 'gemini-2.5-flash-lite',
        cacheHit: false,
        inputTokens: inputTokenEstimate,
        outputTokens: AiUsageLogger.estimateTokens(content),
        status: 'ok',
      );

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch == null) return _fallbackParse(input);

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final txns = (parsed['transactions'] as List?) ?? [];

      final modelResults = txns
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
      return _reconcileModelResults(input, modelResults);
    } catch (e) {
      debugPrint('[GeminiInputParser] parseInput error: $e');
      AiUsageLogger.logGemini(
        feature: 'entry_parse',
        model: 'gemini-2.5-flash-lite',
        cacheHit: false,
        inputTokens: inputTokenEstimate,
        outputTokens: 0,
        status: 'error',
      );
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

  @visibleForTesting
  List<ParsedResult> debugFallbackParse(String input) => _fallbackParse(input);

  @visibleForTesting
  List<ParsedResult> debugReconcileModelResults(
    String input,
    List<ParsedResult> modelResults,
  ) => _reconcileModelResults(input, modelResults);

  List<ParsedResult> _reconcileModelResults(
    String input,
    List<ParsedResult> modelResults,
  ) {
    if (modelResults.isEmpty) return _fallbackParse(input);

    final deterministic = _fallbackParse(input);
    if (deterministic.isEmpty) return modelResults;

    final shouldPreferDeterministic =
        (_looksLikeItemizedReceipt(input) ||
            _looksLikeMultiOrderReceipt(input)) &&
        deterministic.length > modelResults.length;
    if (shouldPreferDeterministic) return deterministic;

    return modelResults;
  }

  _LocalParseDecision _localParseDecision(String input) {
    final results = _fallbackParse(input);
    if (results.isEmpty) {
      return const _LocalParseDecision(
        results: [],
        confidence: 0,
        reason: 'empty',
      );
    }

    final isItemizedReceipt = _looksLikeItemizedReceipt(input);
    if (isItemizedReceipt && results.length >= 2) {
      return _LocalParseDecision(
        results: results,
        confidence: 0.95,
        reason: 'itemized_receipt',
      );
    }

    final isMultiOrderReceipt = _looksLikeMultiOrderReceipt(input);
    if (isMultiOrderReceipt && results.length >= 2) {
      return _LocalParseDecision(
        results: results,
        confidence: 0.95,
        reason: 'multi_order_receipt',
      );
    }

    if (_looksLikeReceipt(input) &&
        results.length == 1 &&
        _hasStrongReceiptTotal(input) &&
        _hasReceiptIdentity(input)) {
      return _LocalParseDecision(
        results: results,
        confidence: 0.86,
        reason: 'single_receipt_total',
      );
    }

    return _LocalParseDecision(
      results: results,
      confidence: _looksLikeReceipt(input) ? 0.65 : 0.35,
      reason: _looksLikeReceipt(input) ? 'ambiguous_receipt' : 'natural_text',
    );
  }

  List<ParsedResult> _fallbackParse(String input) {
    final results = <ParsedResult>[];
    final seen = <String>{};

    void addResult(double amount, String note, {String? categorySource}) {
      if (amount <= 0 || amount >= 1000000) return;
      final normalizedNote = note.trim().replaceAll(RegExp(r'\s+'), ' ');
      final key = '${amount.toStringAsFixed(2)}|$normalizedNote';
      if (!seen.add(key)) return;

      final source =
          categorySource ??
          (normalizedNote.isEmpty ? input : '$normalizedNote $input');
      results.add(
        ParsedResult(
          amount: amount,
          category: _guessCategory(source),
          note: normalizedNote.isEmpty
              ? input.substring(0, input.length.clamp(0, 30)).trim()
              : normalizedNote,
          type:
              RegExp(
                r'salary|income|bonus|gift|refund|reimbursement|工资|收入|奖金|红包|退款|报销',
                caseSensitive: false,
              ).hasMatch(source)
              ? 'income'
              : 'expense',
        ),
      );
    }

    if (_looksLikeReceipt(input)) {
      final orderResults = _fallbackParseMultiOrderReceipt(input);
      if (orderResults.isNotEmpty) {
        for (final result in orderResults) {
          addResult(
            result.amount,
            result.note,
            categorySource: result.categorySource,
          );
        }
        return results;
      }

      final itemizedResults = _fallbackParseItemizedReceipt(input);
      if (itemizedResults.isNotEmpty) {
        for (final result in itemizedResults) {
          addResult(result.amount, result.note);
        }
        return results;
      }

      final receiptResult = _fallbackParseReceipt(input);
      if (receiptResult != null) {
        addResult(receiptResult.amount, receiptResult.note);
        return results;
      }
    }

    // Natural text: "coffee 5", "lunch $12.50", "午饭 35".
    final inlinePattern = RegExp(
      r'([\p{L}\p{Script=Han}][\p{L}\p{Script=Han}\d\s\-_/·]{0,28}?)\s*([$¥￥]?\s*\d{1,7}(?:[,.]\d{1,2})?)',
      unicode: true,
      caseSensitive: false,
    );
    for (final match in inlinePattern.allMatches(input)) {
      final note = _cleanFallbackNote(match.group(1) ?? '');
      final amount = _parseFallbackAmount(match.group(2) ?? '');
      if (_looksLikeDateOrCode(note, amount)) continue;
      addResult(amount, note);
    }

    // Non-obvious receipt text: still prefer a single receipt result after
    // natural-language parsing fails.
    final receiptResult = _fallbackParseReceipt(input);
    if (receiptResult != null && results.isEmpty) {
      addResult(receiptResult.amount, receiptResult.note);
    }
    return results;
  }

  List<({double amount, String note, String categorySource})>
  _fallbackParseMultiOrderReceipt(String input) {
    if (!_looksLikeMultiOrderReceipt(input)) return const [];

    final blocks = input
        .split(RegExp(r'(?:\r?\n\s*){2,}'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();
    final results = <({double amount, String note, String categorySource})>[];
    for (final block in blocks) {
      if (!_looksLikeConfirmedOrderBlock(block)) continue;
      final parsed = _fallbackParseReceipt(block);
      if (parsed == null) continue;
      results.add((
        amount: parsed.amount,
        note: parsed.note,
        categorySource: '${parsed.note} $block',
      ));
    }
    return results.length >= 2 ? results : const [];
  }

  List<({double amount, String note})> _fallbackParseItemizedReceipt(
    String input,
  ) {
    if (!_looksLikeItemizedReceipt(input)) return const [];

    final results = <({double amount, String note})>[];
    final lines = input
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (final line in lines) {
      if (_isReceiptNoiseLine(line)) continue;
      if (_isReceiptHeaderLine(line)) continue;
      if (_isReceiptSummaryLine(line)) continue;
      if (_isReceiptMetadataLine(line)) continue;

      final match = _amountPattern.allMatches(line).lastOrNull;
      if (match == null) continue;

      final amount = _parseFallbackAmount(match.group(1) ?? '');
      if (amount <= 0 || amount >= 1000000) continue;

      var noteSource = line.substring(0, match.start).trim();
      noteSource = noteSource.replaceFirst(
        RegExp(r'\s+\d+(?:[,.]\d{1,2})?\s*$'),
        '',
      );
      final note = _cleanFallbackNote(noteSource);
      if (note.isEmpty) continue;
      if (_looksLikeDateOrCode(note, amount)) continue;
      if (!_looksLikeItemName(note)) continue;

      results.add((amount: amount, note: note));
    }

    return results.length >= 2 ? results : const [];
  }

  ({double amount, String note})? _fallbackParseReceipt(String input) {
    final lines = input
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final candidates = <({double amount, String note, int priority})>[];
    for (final line in lines) {
      if (_isReceiptNoiseLine(line)) continue;
      final priority = _receiptLinePriority(line);
      final amountMatches = _amountPattern.allMatches(line);
      for (final match in amountMatches) {
        final amount = _parseFallbackAmount(match.group(1) ?? '');
        final note = _cleanFallbackNote(
          line.replaceFirst(match.group(0) ?? '', ''),
        );
        if (_looksLikeDateOrCode(note, amount)) continue;
        candidates.add((amount: amount, note: note, priority: priority));
      }
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      return b.amount.compareTo(a.amount);
    });
    final best = candidates.first;
    return (
      amount: best.amount,
      note: _guessReceiptNote(input, fallback: best.note),
    );
  }

  static final RegExp _amountPattern = RegExp(
    r'((?:USD|SGD|PHP|THB|MYR|RM|HKD|TWD|JPY|KRW|VND|IDR|AUD|CAD|EUR|GBP)?\s*[$¥￥€£₱฿₩]?\s*\d{1,9}(?:[,.]\d{1,2})?)',
    caseSensitive: false,
  );

  bool _looksLikeReceipt(String input) {
    final lower = input.toLowerCase();
    final hasReceiptKeyword = RegExp(
      r'receipt|invoice|subtotal|tax|vat|gst|total|amount due|paid|payment|change|cashier|terminal|auth|approval|merchant|store|restaurant|thank you|合计|总计|实付',
      caseSensitive: false,
    ).hasMatch(lower);
    final lineCount = input.split(RegExp(r'[\r\n]+')).length;
    final amountCount = _amountPattern.allMatches(input).length;
    return hasReceiptKeyword && (lineCount >= 3 || amountCount >= 2);
  }

  bool _looksLikeItemizedReceipt(String input) {
    final lower = input.toLowerCase();
    if (RegExp(
      r'hotel|booking|ticket|flight|train|order|invoice|confirmation|reservation|酒店|火车票|机票|订单|订门票|改签|退票',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return false;
    }
    final hasTableSignal = RegExp(
      r'\bitem\b|\bquantity\b|\bqty\b|\bprice\b|shopping receipt|grocery|freshmart|超市|小票|商品|数量|单价',
      caseSensitive: false,
    ).hasMatch(lower);
    final lineItemMatches = input.split(RegExp(r'[\r\n]+')).where((line) {
      final clean = line.trim();
      if (clean.isEmpty || _isReceiptNoiseLine(clean)) return false;
      if (_isReceiptHeaderLine(clean)) return false;
      final amount = _amountPattern.allMatches(clean).lastOrNull;
      if (amount == null) return false;
      final note = _cleanFallbackNote(clean.substring(0, amount.start));
      return _looksLikeItemName(note);
    }).length;
    return hasTableSignal && lineItemMatches >= 2;
  }

  bool _looksLikeMultiOrderReceipt(String input) {
    final lower = input.toLowerCase();
    final orderKeywordCount = RegExp(
      r'hotel|booking|ticket|flight|train|issued|confirmed|paid amount|amount paid|酒店|火车票|机票|门票|已确认|出票成功|已购|实付款|合计',
      caseSensitive: false,
    ).allMatches(lower).length;
    final amountCount = _amountPattern.allMatches(input).length;
    return orderKeywordCount >= 2 && amountCount >= 2;
  }

  bool _looksLikeConfirmedOrderBlock(String block) {
    final lower = block.toLowerCase();
    if (!_amountPattern.hasMatch(block)) return false;
    if (RegExp(
      r'recommend|recommended|popular attraction|for you|为你推荐|热门景点|精选一日游',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return false;
    }
    return RegExp(
      r'hotel|booking|ticket|flight|train|issued|confirmed|paid amount|amount paid|酒店|火车票|机票|门票|已确认|出票成功|已购|实付款|合计',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  int _receiptLinePriority(String line) {
    final lower = line.toLowerCase();
    if (RegExp(
      r'grand total|amount due|balance due|total paid|total payment|net amount|card sale|total charge|actual paid|paid amount|amount paid|实付|应付|付款',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 0;
    }
    if (RegExp(r'\btotal\b|合计|总计|金额', caseSensitive: false).hasMatch(lower)) {
      return 1;
    }
    return 3;
  }

  bool _hasStrongReceiptTotal(String input) {
    return RegExp(
      r'grand total|amount due|balance due|total paid|total payment|net amount|card sale|total charge|actual paid|paid amount|amount paid|实付|应付|付款',
      caseSensitive: false,
    ).hasMatch(input);
  }

  bool _hasReceiptIdentity(String input) {
    final lines = input
        .split(RegExp(r'[\r\n]+'))
        .map((line) => _cleanFallbackNote(line))
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.any((line) {
      if (RegExp(
        r'\d+[,.]\d{1,2}|total|subtotal|tax|vat|gst|paid|payment|amount|invoice|order|terminal|auth|approval|date|time|合计|总计|金额|付款',
        caseSensitive: false,
      ).hasMatch(line)) {
        return false;
      }
      return RegExp(r'[\p{L}\p{Script=Han}]', unicode: true).hasMatch(line);
    });
  }

  bool _isReceiptNoiseLine(String line) {
    final lower = line.toLowerCase();
    if (_receiptLinePriority(line) <= 1) return false;
    return RegExp(
      r'subtotal|sub total|tax|vat|gst|discount|coupon|service charge|suggested tip|tip|change|cash tendered|tendered|balance|card(?:\s|#|no)|auth|approval|invoice|order|terminal|ref(?:erence)?|points?|member',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  bool _isReceiptHeaderLine(String line) {
    return RegExp(
      r'^\s*(shopping receipt|receipt|item\s+quantity\s+price|item\s+qty\s+price|quantity|qty|price|store|address|phone|date|time|thank you|商品|数量|单价)\s*:?\s*$',
      caseSensitive: false,
    ).hasMatch(line.trim());
  }

  bool _isReceiptSummaryLine(String line) {
    return RegExp(
      r'\b(subtotal|sub total|tax|vat|gst|total|grand total|amount due|paid|payment)\b|小计|税|合计|总计|实付|付款',
      caseSensitive: false,
    ).hasMatch(line.trim());
  }

  bool _isReceiptMetadataLine(String line) {
    return RegExp(
      r'^\s*(store|address|phone|date|time|cashier|terminal|merchant)\s*:|thank you|谢谢',
      caseSensitive: false,
    ).hasMatch(line.trim());
  }

  bool _looksLikeItemName(String note) {
    final clean = note.trim();
    if (clean.length < 2) return false;
    if (RegExp(r'^\d+$').hasMatch(clean)) return false;
    return RegExp(r'[\p{L}\p{Script=Han}]', unicode: true).hasMatch(clean);
  }

  double _parseFallbackAmount(String raw) {
    final cleaned = raw
        .replaceAll(
          RegExp(
            r'USD|SGD|PHP|THB|MYR|RM|HKD|TWD|JPY|KRW|VND|IDR|AUD|CAD|EUR|GBP',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[$¥￥€£₱฿₩,\s]'), '')
        .replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  String _cleanFallbackNote(String raw) {
    return raw
        .replaceAll(RegExp(r'[$¥￥€£₱฿₩]'), '')
        .replaceAll(
          RegExp(
            r'\b(?:USD|SGD|PHP|THB|MYR|RM|HKD|TWD|JPY|KRW|VND|IDR|AUD|CAD|EUR|GBP)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[：:·\\-_/]+|[：:·\\-_/]+$'), '')
        .trim();
  }

  bool _looksLikeDateOrCode(String note, double amount) {
    if (amount <= 0) return true;
    if (RegExp(r'\b20\d{2}\b|\b\d{1,2}[:/.-]\d{1,2}\b').hasMatch(note)) {
      return true;
    }
    return false;
  }

  String _guessReceiptNote(String input, {String fallback = ''}) {
    final lines = input
        .split(RegExp(r'[\r\n]+'))
        .map((line) => _cleanFallbackNote(line))
        .where((line) {
          if (line.isEmpty) return false;
          if (RegExp(
            r'\d{4}|\d+[,.]\d{1,2}|total|subtotal|tax|vat|gst|paid|payment|amount|invoice|order|terminal|auth|approval|合计|总计|金额',
            caseSensitive: false,
          ).hasMatch(line)) {
            return false;
          }
          return true;
        })
        .toList();
    if (lines.isNotEmpty) {
      return lines.first.substring(0, lines.first.length.clamp(0, 40));
    }
    final cleanedFallback = _cleanFallbackNote(fallback);
    return cleanedFallback.isEmpty ? 'Receipt' : cleanedFallback;
  }

  String _guessCategory(String text) {
    final t = text.toLowerCase();
    if (RegExp(
      r'breakfast|lunch|dinner|hotpot|takeout|meal|restaurant|coffee|cafe|milk tea|早餐|午饭|晚饭|火锅|外卖|咖啡|奶茶|吃饭',
    ).hasMatch(t)) {
      return t.contains('coffee') || t.contains('cafe') || t.contains('咖啡')
          ? 'coffee'
          : 'food';
    }
    if (RegExp(
      r'taxi|uber|metro|subway|bus|train|flight|railway|打车|地铁|公交|火车|机票|车票',
    ).hasMatch(t)) {
      return 'transport';
    }
    if (RegExp(
      r'hotel|lodging|resort|travel|tour|universal studios|ticket|酒店|住宿|旅行|旅游|景区|门票',
    ).hasMatch(t)) {
      return 'travel';
    }
    if (RegExp(
      r'shopping|store|online store|amazon|taobao|jd|mall|购物|淘宝|京东',
    ).hasMatch(t)) {
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

class _LocalParseDecision {
  const _LocalParseDecision({
    required this.results,
    required this.confidence,
    required this.reason,
  });

  static const double _skipModelThreshold = 0.82;

  final List<ParsedResult> results;
  final double confidence;
  final String reason;

  bool get shouldSkipModel =>
      results.isNotEmpty && confidence >= _skipModelThreshold;
}
