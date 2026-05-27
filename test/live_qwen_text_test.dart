import 'dart:io';

import 'package:ai_accounting_app/services/config_service.dart';
import 'package:ai_accounting_app/services/qwen_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final runLive = Platform.environment['RUN_LIVE_QWEN'] == '1';

  group(
    'live Qwen text parsing',
    skip: runLive ? false : 'RUN_LIVE_QWEN != 1',
    () {
      test(
        'parses common Chinese multi-entry input',
        () async {
          ConfigService.instance.resetForTest();
          await ConfigService.instance.load();

          expect(ConfigService.instance.isQwenConfigured, isTrue);

          final results = await QwenService().parseInput('午饭25，打车18');

          expect(results.map((item) => item.amount), containsAll([25, 18]));
          expect(results.every((item) => item.type == 'expense'), isTrue);
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    },
  );
}
