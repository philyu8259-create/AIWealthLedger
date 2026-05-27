import 'dart:io';

import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ConfigService> _loadEnv(
  Map<String, String> entries, {
  AppFlavor? flavor,
}) async {
  return _loadEnvWithDefines(
    entries,
    compileTimeOverrides: null,
    flavor: flavor,
  );
}

Future<ConfigService> _loadEnvWithDefines(
  Map<String, String> entries, {
  Map<String, String>? compileTimeOverrides,
  AppFlavor? flavor,
}) async {
  final dir = await Directory.systemTemp.createTemp(
    'ai-accounting-config-service-',
  );
  final file = File('${dir.path}/.env');
  final content = entries.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('\n');
  await file.writeAsString(content);
  ConfigService.instance.resetForTest();
  ConfigService.instance.setCompileTimeEnvOverrideForTest(compileTimeOverrides);
  ConfigService.instance.setBuildFlavorOverrideForTest(flavor);
  await ConfigService.instance.loadFromPath(file.path);
  return ConfigService.instance;
}

void main() {
  group('ConfigService', () {
    test(
      'Android Google sign-in config helper recognizes web server client id',
      () async {
        final service = await _loadEnv({
          'GOOGLE_SERVER_CLIENT_ID': 'server-id',
        }, flavor: AppFlavor.intl);

        expect(service.googleServerClientId, 'server-id');
        expect(service.googleAndroidClientId, isEmpty);
        expect(service.isGoogleSignInConfigured, isTrue);
        expect(service.isGoogleSignInFullyConfigured, isTrue);
        expect(service.isGoogleSignInAndroidConfigured, isTrue);
        expect(service.isGoogleSignInAndroidFullyConfigured, isTrue);
        expect(service.isGoogleSignInIosFullyConfigured, isFalse);
      },
    );

    test('Android optional GOOGLE_ANDROID_CLIENT_ID 不影响全量判定', () async {
      final service = await _loadEnv({
        'GOOGLE_ANDROID_CLIENT_ID': 'android-id',
        'GOOGLE_SERVER_CLIENT_ID': 'server-id',
      }, flavor: AppFlavor.intl);

      expect(service.googleServerClientId, 'server-id');
      expect(service.googleAndroidClientId, 'android-id');
      expect(service.isGoogleSignInAndroidFullyConfigured, isTrue);
    });

    test('iOS 全量配置仍要求三项配置', () async {
      final missingReversed = await _loadEnv({
        'GOOGLE_IOS_CLIENT_ID': 'ios-id',
        'GOOGLE_SERVER_CLIENT_ID': 'server-id',
      }, flavor: AppFlavor.intl);
      expect(missingReversed.isGoogleSignInIosFullyConfigured, isFalse);

      final iosFull = await _loadEnv({
        'GOOGLE_IOS_CLIENT_ID': 'ios-id',
        'GOOGLE_SERVER_CLIENT_ID': 'server-id',
        'GOOGLE_IOS_REVERSED_CLIENT_ID': 'reversed-ios-id',
      }, flavor: AppFlavor.intl);
      expect(iosFull.isGoogleSignInIosFullyConfigured, isTrue);
    });

    test('本地 .env 值优先于 dart-define 兜底', () async {
      final service = await _loadEnvWithDefines(
        {'QWEN_API_KEY': 'env-qwen', 'GOOGLE_SERVER_CLIENT_ID': 'env-gsi'},
        compileTimeOverrides: {
          'QWEN_API_KEY': 'define-qwen',
          'GOOGLE_SERVER_CLIENT_ID': 'define-gsi',
        },
        flavor: AppFlavor.intl,
      );

      expect(service.qwenApiKey, isEmpty);
      expect(service.isQwenConfigured, isFalse);
      expect(service.googleServerClientId, 'env-gsi');
    });

    test('QWEN_API_KEY 缺失时可由 dart-define 回退，isQwenConfigured 为 true', () async {
      final service = await _loadEnvWithDefines(
        {},
        compileTimeOverrides: {'QWEN_API_KEY': 'define-qwen'},
        flavor: AppFlavor.cn,
      );

      expect(service.qwenApiKey, 'define-qwen');
      expect(service.isQwenConfigured, isTrue);
    });

    test('空字符串 .env 值也允许 dart-define 回退', () async {
      final service = await _loadEnvWithDefines(
        {'QWEN_API_KEY': ''},
        compileTimeOverrides: {'QWEN_API_KEY': 'define-qwen'},
        flavor: AppFlavor.cn,
      );

      expect(service.qwenApiKey, 'define-qwen');
      expect(service.isQwenConfigured, isTrue);
    });

    test('CN AI 不存在密钥时应表现为未接入', () async {
      final service = await _loadEnvWithDefines(
        {},
        compileTimeOverrides: {'QWEN_API_KEY': ''},
        flavor: AppFlavor.cn,
      );

      expect(service.qwenApiKey, isEmpty);
      expect(service.isQwenConfigured, isFalse);
    });

    test('CN build ignores intl-only Google and Gemini values', () async {
      final service = await _loadEnvWithDefines({
        'GEMINI_API_KEY': 'gemini',
        'GOOGLE_VISION_API_KEY': 'vision',
        'GOOGLE_SERVER_CLIENT_ID': 'server-id',
        'QWEN_API_KEY': 'qwen',
      }, flavor: AppFlavor.cn);

      expect(service.geminiApiKey, isEmpty);
      expect(service.googleVisionApiKey, isEmpty);
      expect(service.googleServerClientId, isEmpty);
      expect(service.isGoogleSignInConfigured, isFalse);
      expect(service.qwenApiKey, 'qwen');
    });

    test('INTL build ignores cn-only provider values', () async {
      final service = await _loadEnvWithDefines({
        'QWEN_API_KEY': 'qwen',
        'BAIDU_AK': 'ak',
        'BAIDU_SK': 'sk',
        'ALIYUN_ASR_APP_KEY': 'asr',
        'GEMINI_API_KEY': 'gemini',
      }, flavor: AppFlavor.intl);

      expect(service.qwenApiKey, isEmpty);
      expect(service.baiduAk, isEmpty);
      expect(service.aliyunAsrAppKey, isEmpty);
      expect(service.geminiApiKey, 'gemini');
    });
  });
}
