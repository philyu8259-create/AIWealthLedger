import 'dart:io';

import 'package:ai_accounting_app/l10n/app_string_keys.dart';
import 'package:ai_accounting_app/l10n/app_strings.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:ai_accounting_app/services/intl_auth_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGoogleSignInClient implements GoogleSignInClient {
  _FakeGoogleSignInClient(this.result);

  final GoogleSignInAccountInfo? result;

  int signOutCalls = 0;
  int signInCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  Future<GoogleSignInAccountInfo?> signIn() async {
    signInCalls += 1;
    return result;
  }
}

Future<ConfigService> _loadEnv(Map<String, String> entries) async {
  final dir = await Directory.systemTemp.createTemp(
    'ai-accounting-intl-auth-config-',
  );
  final file = File('${dir.path}/.env');
  final content = entries.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('\n');
  await file.writeAsString(content);
  ConfigService.instance.resetForTest();
  await ConfigService.instance.loadFromPath(file.path);
  return ConfigService.instance;
}

Future<SharedPreferences> _initPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('IntlAuthService Google sign-in Android config', () {
    test('Android 端缺少 GOOGLE_SERVER_CLIENT_ID 时给出明确错误', () async {
      await _loadEnv({'GOOGLE_IOS_CLIENT_ID': 'ios-client'});
      final prefs = await _initPrefs();
      final fakeGoogle = _FakeGoogleSignInClient(
        const GoogleSignInAccountInfo(
          email: 'fake@gmail.com',
          displayName: 'Fake',
        ),
      );

      final service = IntlAuthService(
        prefs,
        googleSignInClientFactory:
            ({
              required List<String> scopes,
              String? clientId,
              String? serverClientId,
            }) => fakeGoogle,
        isIosPlatform: () => false,
        isAndroidPlatform: () => true,
      );

      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message contains GOOGLE_SERVER_CLIENT_ID',
            contains('GOOGLE_SERVER_CLIENT_ID'),
          ),
        ),
      );
      expect(fakeGoogle.signOutCalls, 0);
      expect(fakeGoogle.signInCalls, 0);
    });

    test('iOS 仍保留 3 项校验', () async {
      await _loadEnv({'GOOGLE_IOS_CLIENT_ID': 'ios-client'});
      final prefs = await _initPrefs();
      final fakeGoogle = _FakeGoogleSignInClient(
        const GoogleSignInAccountInfo(
          email: 'fake@gmail.com',
          displayName: 'Fake',
        ),
      );

      final service = IntlAuthService(
        prefs,
        googleSignInClientFactory:
            ({
              required List<String> scopes,
              String? clientId,
              String? serverClientId,
            }) => fakeGoogle,
        isIosPlatform: () => true,
        isAndroidPlatform: () => false,
      );

      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message contains GOOGLE_IOS_CLIENT_ID',
            allOf(
              contains('GOOGLE_SERVER_CLIENT_ID'),
              contains('GOOGLE_IOS_REVERSED_CLIENT_ID'),
            ),
          ),
        ),
      );
      expect(fakeGoogle.signOutCalls, 0);
      expect(fakeGoogle.signInCalls, 0);
    });

    test('Android 可不带 iOS 变量成功进入 Google 登录流程', () async {
      await _loadEnv({'GOOGLE_SERVER_CLIENT_ID': 'server-id'});
      final prefs = await _initPrefs();
      final fakeGoogle = _FakeGoogleSignInClient(null);

      final service = IntlAuthService(
        prefs,
        googleSignInClientFactory:
            ({
              required List<String> scopes,
              String? clientId,
              String? serverClientId,
            }) => fakeGoogle,
        isIosPlatform: () => false,
        isAndroidPlatform: () => true,
      );

      await expectLater(
        service.signInWithGoogle(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message contains cancelled',
            contains('已取消 Google 登录'),
          ),
        ),
      );
      expect(fakeGoogle.signOutCalls, 1);
      expect(fakeGoogle.signInCalls, 1);
    });
  });

  group('IntlAuthService Apple', () {
    test('Apple 登录入口只在 iOS 平台展示', () {
      expect(supportsAppleSignInOnTargetPlatform(TargetPlatform.iOS), isTrue);
      expect(
        supportsAppleSignInOnTargetPlatform(TargetPlatform.android),
        isFalse,
      );
      expect(
        supportsAppleSignInOnTargetPlatform(TargetPlatform.macOS),
        isFalse,
      );
    });

    test('Android 国际登录副标题不再承诺 Apple 登录', () {
      final zh = AppStrings.forLocale(
        const Locale('zh'),
      ).text(AppStringKeys.intlAuthSubtitleAndroid);
      final en = AppStrings.forLocale(
        const Locale('en'),
      ).text(AppStringKeys.intlAuthSubtitleAndroid);

      expect(zh, contains('Google'));
      expect(en, contains('Google'));
      expect(zh, isNot(contains('Apple')));
      expect(en, isNot(contains('Apple')));
    });

    test('Android 端 Apple 登录继续显式不支持', () async {
      await _loadEnv({'GOOGLE_SERVER_CLIENT_ID': 'server-id'});
      final prefs = await _initPrefs();
      final service = IntlAuthService(
        prefs,
        isIosPlatform: () => false,
        isAndroidPlatform: () => true,
      );

      await expectLater(
        service.signInWithApple(),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.toString(),
            'message contains apple only ios',
            contains('Apple 登录当前先只接 iOS'),
          ),
        ),
      );
    });
  });
}
