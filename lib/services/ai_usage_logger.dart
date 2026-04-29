import 'package:flutter/foundation.dart';

class AiUsageLogger {
  const AiUsageLogger._();

  static int estimateTokens(String text) => (text.length / 4).ceil();

  static void logGemini({
    required String feature,
    required String model,
    required bool cacheHit,
    required int inputTokens,
    required int outputTokens,
    required String status,
  }) {
    debugPrint(
      '[GeminiUsage] feature=$feature model=$model cacheHit=$cacheHit inputTokens~$inputTokens outputTokens~$outputTokens status=$status',
    );
  }
}
