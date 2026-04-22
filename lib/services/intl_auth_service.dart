import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../features/accounting/data/datasources/i_account_entry_datasource.dart';
import '../app/app_flavor.dart';
import 'app_profile_service.dart';
import 'config_service.dart';
import 'demo_data_seeder.dart';
import 'injection.dart';
import 'stock_service.dart';
import 'vip_service.dart';

class IntlAuthService {
  IntlAuthService(this._prefs);

  final SharedPreferences _prefs;

  static const _loggedInKey = 'has_logged_in';
  static const _accountKey = 'logged_in_phone';
  static const _emailKey = 'logged_in_email';
  static const _providerKey = 'logged_in_auth_provider';
  static const _displayNameKey = 'logged_in_display_name';
  static const _appleEmailPrefix = 'apple_identity_email_';
  static const _appleAccountKeyPrefix = 'apple_identity_account_key_';
  static const _intlDemoEmail = 'demo@aimoneyledger.app';

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  String _maskValue(String? value) {
    if (value == null || value.isEmpty) return '(empty)';
    if (value.length <= 6) return '${value.substring(0, 1)}***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
  }

  Future<void> signInWithEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    debugPrint(
      '[IntlAuthService] signInWithEmail blocked: ${_maskValue(normalizedEmail)}',
    );
    throw StateError(
      _message(
        '邮箱登录当前不可用，请稍后再试',
        'Email sign in is currently unavailable. Please try again later.',
      ),
    );
  }

  Future<void> signInWithIntlDemo() async {
    debugPrint('[IntlAuthService] signInWithIntlDemo start');
    await _signInWithIntlDemoEmail(_intlDemoEmail);
  }

  Future<void> signInWithGoogle() async {
    debugPrint('[IntlAuthService] signInWithGoogle start');
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw UnsupportedError(
        _message(
          'Google 登录当前只支持 iOS 和 Android',
          'Google sign in is currently supported on iOS and Android only',
        ),
      );
    }
    final missing = <String>[
      if (Platform.isIOS && ConfigService.instance.googleIosClientId.isEmpty)
        'GOOGLE_IOS_CLIENT_ID',
      if (ConfigService.instance.googleServerClientId.isEmpty)
        'GOOGLE_SERVER_CLIENT_ID',
      if (Platform.isIOS &&
          ConfigService.instance.googleIosReversedClientId.isEmpty)
        'GOOGLE_IOS_REVERSED_CLIENT_ID',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        _message(
          'Google 登录还缺少配置: ${missing.join(', ')}',
          'Google sign in is missing configuration: ${missing.join(', ')}',
        ),
      );
    }

    final signIn = GoogleSignIn(
      scopes: const ['email'],
      clientId: Platform.isIOS
          ? ConfigService.instance.googleIosClientId
          : null,
      serverClientId: ConfigService.instance.googleServerClientId.isEmpty
          ? null
          : ConfigService.instance.googleServerClientId,
    );

    await signIn.signOut();
    final account = await signIn.signIn();
    if (account == null) {
      debugPrint('[IntlAuthService] signInWithGoogle cancelled');
      throw StateError(
        _message('已取消 Google 登录', 'Google sign in was cancelled'),
      );
    }

    final email = account.email.trim().toLowerCase();
    debugPrint(
      '[IntlAuthService] signInWithGoogle success: email=${_maskValue(email)}, displayName=${account.displayName ?? '(null)'}',
    );
    await _completeSignIn(
      accountKey: email,
      email: email,
      provider: 'google',
      displayName: account.displayName?.trim().isNotEmpty == true
          ? account.displayName!.trim()
          : email,
    );
  }

  Future<void> signInWithApple() async {
    debugPrint('[IntlAuthService] signInWithApple start');
    if (!Platform.isIOS) {
      throw UnsupportedError(
        _message(
          'Apple 登录当前先只接 iOS',
          'Apple sign in is currently available on iOS only',
        ),
      );
    }

    if (!await SignInWithApple.isAvailable()) {
      throw UnsupportedError(
        _message(
          '当前设备或环境暂不支持 Apple 登录，请改用真机并确认已开启 Sign in with Apple capability',
          'Apple sign in is not available in the current device or environment. Please use a real iPhone and make sure the Sign in with Apple capability is enabled.',
        ),
      );
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      debugPrint(
        '[IntlAuthService] signInWithApple credential: user=${_maskValue(credential.userIdentifier)}, email=${_maskValue(credential.email)}',
      );

      final userIdentifier = credential.userIdentifier?.trim();
      final cachedEmail = userIdentifier == null || userIdentifier.isEmpty
          ? null
          : _prefs.getString('$_appleEmailPrefix$userIdentifier');
      final email = (credential.email ?? cachedEmail ?? '')
          .trim()
          .toLowerCase();
      final displayName = _composeAppleDisplayName(credential, email);
      final stableAccountKey = _stableAppleAccountKey(userIdentifier);
      final legacyAccountKey = email.isNotEmpty ? email : null;

      if (userIdentifier != null && userIdentifier.isNotEmpty) {
        await _prefs.setString(
          '$_appleAccountKeyPrefix$userIdentifier',
          stableAccountKey,
        );
        if (email.isNotEmpty) {
          await _prefs.setString('$_appleEmailPrefix$userIdentifier', email);
        }
      }

      await _migrateAppleScopedDataIfNeeded(
        legacyAccountKey: legacyAccountKey,
        stableAccountKey: stableAccountKey,
      );

      debugPrint(
        '[IntlAuthService] signInWithApple resolved: accountKey=${_maskValue(stableAccountKey)}, email=${_maskValue(email)}, displayName=$displayName',
      );
      await _completeSignIn(
        accountKey: stableAccountKey,
        email: email.isEmpty ? null : email,
        provider: 'apple',
        displayName: displayName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint(
        '[IntlAuthService] signInWithApple authorization error: code=${e.code}, message=${e.message}',
      );
      if (_isAppleAccountMissingMessage(e.message)) {
        throw StateError(
          _message(
            '当前 iPhone 还没有在系统设置里登录 Apple 账户，请先到“设置”里登录 Apple ID 后再试',
            'This iPhone is not signed in to an Apple account yet. Please sign in to your Apple ID in Settings and try again.',
          ),
        );
      }

      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          throw StateError(
            _message('已取消 Apple 登录', 'Apple sign in was cancelled'),
          );
        case AuthorizationErrorCode.notInteractive:
          throw StateError(
            _message(
              'Apple 登录当前无法弹出交互界面，请稍后重试',
              'Apple sign in could not present an interactive prompt right now. Please try again.',
            ),
          );
        case AuthorizationErrorCode.notHandled:
        case AuthorizationErrorCode.invalidResponse:
        case AuthorizationErrorCode.failed:
        case AuthorizationErrorCode.unknown:
          throw StateError(
            _message(
              'Apple 登录失败，请确认真机 capability、账号状态和回调配置是否正确',
              'Apple sign in failed. Please verify the real-device capability, Apple account state, and callback configuration.',
            ),
          );
      }
    } on SignInWithAppleNotSupportedException {
      debugPrint('[IntlAuthService] signInWithApple not supported');
      throw UnsupportedError(
        _message(
          '当前环境不支持 Apple 登录，请改用真机并确认系统版本和 capability 配置正确',
          'Apple sign in is not supported in the current environment. Please use a real iPhone and verify the OS version and capability setup.',
        ),
      );
    }
  }

  Future<void> _signInWithIntlDemoEmail(String email) async {
    debugPrint(
      '[IntlAuthService] _signInWithIntlDemoEmail: ${_maskValue(email)}',
    );
    await DemoDataSeeder.seed(variant: DemoDataVariant.intl);
    await _prefs.setBool(_loggedInKey, true);
    await _prefs.setString(_accountKey, 'DemoAccount');
    await _prefs.setString(_emailKey, email);
    await _prefs.setString(_providerKey, 'demo');
    await _prefs.setString(_displayNameKey, 'AI Money Demo');
    await getIt<AppProfileService>().lockCurrentMode();

    try {
      await getIt<VipService>().restorePurchases();
      debugPrint('[IntlAuthService] intl demo restorePurchases done');
    } catch (e) {
      debugPrint('[IntlAuthService] intl demo restorePurchases error: $e');
    }
  }

  Future<void> _completeSignIn({
    required String accountKey,
    required String provider,
    String? email,
    String? displayName,
  }) async {
    debugPrint(
      '[IntlAuthService] _completeSignIn: provider=$provider, account=${_maskValue(accountKey)}, email=${_maskValue(email)}, displayName=${displayName ?? '(null)'}',
    );
    await _prefs.setBool(_loggedInKey, true);
    await _prefs.setString(_accountKey, accountKey);
    await _prefs.setString(_providerKey, provider);
    await getIt<AppProfileService>().lockCurrentMode();

    if (email != null && email.isNotEmpty) {
      await _prefs.setString(_emailKey, email);
    } else {
      await _prefs.remove(_emailKey);
    }

    if (displayName != null && displayName.isNotEmpty) {
      await _prefs.setString(_displayNameKey, displayName);
    } else {
      await _prefs.remove(_displayNameKey);
    }

    await DemoDataSeeder.clear();

    debugPrint('[IntlAuthService] _completeSignIn persisted login state');

    // 登录态先落地，云端恢复改为后台进行，避免登录完成后或下一次冷启动被同步链路拖慢。
    unawaited(_postSignInBootstrap());
  }

  Future<void> _postSignInBootstrap() async {
    debugPrint('[IntlAuthService] _postSignInBootstrap start');
    try {
      await getIt<IAccountEntryDataSource>().restoreFromCloudIfNeeded();
      await getIt<StockService>().restoreFromCloudIfNeeded();
      debugPrint('[IntlAuthService] restoreFromCloudIfNeeded done');
    } catch (e) {
      debugPrint('[IntlAuthService] restoreFromCloudIfNeeded error: $e');
    }

    try {
      await getIt<VipService>().restorePurchases();
      debugPrint('[IntlAuthService] restorePurchases done');
    } catch (e) {
      debugPrint('[IntlAuthService] restorePurchases error: $e');
    }

    try {
      await getIt<VipService>().syncFromCloud();
      debugPrint('[IntlAuthService] syncFromCloud done');
    } catch (e) {
      debugPrint('[IntlAuthService] syncFromCloud error: $e');
    }
    debugPrint('[IntlAuthService] _postSignInBootstrap end');
  }

  String _stableAppleAccountKey(String? userIdentifier) {
    final normalized = userIdentifier?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'apple:unknown';
    }
    return 'apple:$normalized';
  }

  Future<void> _migrateAppleScopedDataIfNeeded({
    required String? legacyAccountKey,
    required String stableAccountKey,
  }) async {
    final normalizedLegacy = legacyAccountKey?.trim();
    if (normalizedLegacy == null ||
        normalizedLegacy.isEmpty ||
        normalizedLegacy == stableAccountKey) {
      return;
    }

    Future<void> copyString(String oldKey, String newKey) async {
      if (_prefs.containsKey(newKey)) return;
      final value = _prefs.getString(oldKey);
      if (value != null && value.isNotEmpty) {
        await _prefs.setString(newKey, value);
      }
    }

    Future<void> copyInt(String oldKey, String newKey) async {
      if (_prefs.containsKey(newKey)) return;
      final value = _prefs.getInt(oldKey);
      if (value != null) {
        await _prefs.setInt(newKey, value);
      }
    }

    final legacyScopedId = _sanitizeScopedId(normalizedLegacy);
    final stableScopedId = _sanitizeScopedId(stableAccountKey);

    await copyString('vip_type_$legacyScopedId', 'vip_type_$stableScopedId');
    await copyInt(
      'vip_expire_ms_$legacyScopedId',
      'vip_expire_ms_$stableScopedId',
    );
    await copyInt(
      'last_processed_transaction_date_$legacyScopedId',
      'last_processed_transaction_date_$stableScopedId',
    );
    await copyString(
      'cloud_assets_v2_$legacyScopedId',
      'cloud_assets_v2_$stableScopedId',
    );
    await copyString(
      'stock_positions_v2_$legacyScopedId',
      'stock_positions_v2_$stableScopedId',
    );
    await copyString(
      'stock_deleted_ids_v1_$legacyScopedId',
      'stock_deleted_ids_v1_$stableScopedId',
    );
  }

  String _sanitizeScopedId(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  bool _isAppleAccountMissingMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('sign in to an apple account') ||
        normalized.contains('sign in to your apple id') ||
        normalized.contains('apple account') &&
            normalized.contains('settings') ||
        message.contains('登录 Apple 账户') ||
        message.contains('登录Apple账户') ||
        message.contains('Apple 账户') && message.contains('设置');
  }

  String _composeAppleDisplayName(
    AuthorizationCredentialAppleID credential,
    String email,
  ) {
    final first = credential.givenName?.trim() ?? '';
    final last = credential.familyName?.trim() ?? '';
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    if (full.isNotEmpty) return full;
    if (email.isNotEmpty) return email;
    return _message('Apple 用户', 'Apple User');
  }
}
