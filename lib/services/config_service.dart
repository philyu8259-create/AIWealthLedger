import 'dart:io';
import 'package:flutter/foundation.dart';
import '../app/app_flavor.dart';

/// 统一配置服务 — 从 .env 读取所有环境变量
/// 不依赖 flutter_dotenv，直接解析文件
class ConfigService {
  static ConfigService? _instance;
  Map<String, String> _vars = {};

  /// 便于测试注入：编译期常量从 `String.fromEnvironment` 读取，默认由生产环境默认值决定。
  Map<String, String>? _testCompileTimeEnv;
  AppFlavor? _testBuildFlavor;

  /// 运行期可配的配置键：
  static const List<String> _configKeys = [
    'GEMINI_API_KEY',
    'GOOGLE_VISION_API_KEY',
    'FINNHUB_API_KEY',
    'GOOGLE_IOS_CLIENT_ID',
    'GOOGLE_SERVER_CLIENT_ID',
    'GOOGLE_IOS_REVERSED_CLIENT_ID',
    'GOOGLE_ANDROID_CLIENT_ID',
    'ALIYUN_FC_API',
    'QWEN_API_KEY',
    'BAIDU_AK',
    'BAIDU_SK',
    'OCR_SPACE_API_KEY',
    'ZHITU_API_TOKEN',
    'ALIYUN_ACCESS_KEY_ID',
    'ALIYUN_ACCESS_KEY_SECRET',
    'ALIYUN_ASR_APP_KEY',
  ];

  static const Set<String> _cnOnlyConfigKeys = {
    'QWEN_API_KEY',
    'BAIDU_AK',
    'BAIDU_SK',
    'OCR_SPACE_API_KEY',
    'ZHITU_API_TOKEN',
    'ALIYUN_ACCESS_KEY_ID',
    'ALIYUN_ACCESS_KEY_SECRET',
    'ALIYUN_ASR_APP_KEY',
  };

  static const Set<String> _intlOnlyConfigKeys = {
    'GEMINI_API_KEY',
    'GOOGLE_VISION_API_KEY',
    'FINNHUB_API_KEY',
    'GOOGLE_IOS_CLIENT_ID',
    'GOOGLE_SERVER_CLIENT_ID',
    'GOOGLE_IOS_REVERSED_CLIENT_ID',
    'GOOGLE_ANDROID_CLIENT_ID',
  };

  static const Map<String, String> _compileTimeDefaults = {
    'GEMINI_API_KEY': String.fromEnvironment(
      'GEMINI_API_KEY',
      defaultValue: '',
    ),
    'GOOGLE_VISION_API_KEY': String.fromEnvironment(
      'GOOGLE_VISION_API_KEY',
      defaultValue: '',
    ),
    'FINNHUB_API_KEY': String.fromEnvironment(
      'FINNHUB_API_KEY',
      defaultValue: '',
    ),
    'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue: '',
    ),
    'GOOGLE_SERVER_CLIENT_ID': String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '',
    ),
    'GOOGLE_IOS_REVERSED_CLIENT_ID': String.fromEnvironment(
      'GOOGLE_IOS_REVERSED_CLIENT_ID',
      defaultValue: '',
    ),
    'GOOGLE_ANDROID_CLIENT_ID': String.fromEnvironment(
      'GOOGLE_ANDROID_CLIENT_ID',
      defaultValue: '',
    ),
    'ALIYUN_FC_API': String.fromEnvironment('ALIYUN_FC_API', defaultValue: ''),
    'QWEN_API_KEY': String.fromEnvironment('QWEN_API_KEY', defaultValue: ''),
    'BAIDU_AK': String.fromEnvironment('BAIDU_AK', defaultValue: ''),
    'BAIDU_SK': String.fromEnvironment('BAIDU_SK', defaultValue: ''),
    'OCR_SPACE_API_KEY': String.fromEnvironment(
      'OCR_SPACE_API_KEY',
      defaultValue: '',
    ),
    'ZHITU_API_TOKEN': String.fromEnvironment(
      'ZHITU_API_TOKEN',
      defaultValue: '',
    ),
    'ALIYUN_ACCESS_KEY_ID': String.fromEnvironment(
      'ALIYUN_ACCESS_KEY_ID',
      defaultValue: '',
    ),
    'ALIYUN_ACCESS_KEY_SECRET': String.fromEnvironment(
      'ALIYUN_ACCESS_KEY_SECRET',
      defaultValue: '',
    ),
    'ALIYUN_ASR_APP_KEY': String.fromEnvironment(
      'ALIYUN_ASR_APP_KEY',
      defaultValue: '',
    ),
  };

  ConfigService._();

  static ConfigService get instance {
    _instance ??= ConfigService._();
    return _instance!;
  }

  bool _loaded = false;

  /// 启动时调用一次
  Future<void> load({String? envFilePath}) async {
    if (_loaded) return;
    _vars = {};

    final candidates = <String>[];
    if (envFilePath == null || envFilePath.isEmpty) {
      // 尝试多个路径直到找到 .env
      candidates.addAll(_getEnvCandidates());
    } else {
      candidates.add(envFilePath);
    }

    for (final path in candidates) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          for (final line in content.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            final idx = trimmed.indexOf('=');
            if (idx > 0) {
              final key = trimmed.substring(0, idx).trim();
              final val = trimmed.substring(idx + 1).trim();
              _vars[key] = val;
            }
          }
          debugPrint(
            '[ConfigService] Loaded .env from: $path (${_vars.length} vars)',
          );
          break;
        }
      } catch (e) {
        debugPrint('[ConfigService] Failed: path=$path error=$e');
      }
    }

    _mergeCompileTimeFallback();

    _loaded = true;
  }

  @visibleForTesting
  Future<void> loadFromPath(String envFilePath) async {
    return load(envFilePath: envFilePath);
  }

  @visibleForTesting
  void resetForTest() {
    _vars = {};
    _loaded = false;
    _testCompileTimeEnv = null;
    _testBuildFlavor = null;
  }

  /// 仅测试场景使用：替换用于兜底的编译期配置。
  @visibleForTesting
  void setCompileTimeEnvOverrideForTest(Map<String, String>? values) {
    if (values == null) {
      _testCompileTimeEnv = null;
      return;
    }

    _testCompileTimeEnv = Map<String, String>.from(values);
  }

  @visibleForTesting
  void setBuildFlavorOverrideForTest(AppFlavor? flavor) {
    _testBuildFlavor = flavor;
  }

  /// 生成所有可能的 .env 路径
  List<String> _getEnvCandidates() {
    final candidates = <String>[];
    try {
      // 1. 从 Platform.script 向上查找（最可靠）
      // iOS: Runner.app/Frameworks/App.framework/App → Runner.app/
      // macOS: Runner.app/Contents/Resources/snapshot_blob.dart → Runner.app/
      final scriptPath = Platform.script.toFilePath();
      if (scriptPath.contains('/Frameworks/')) {
        // iOS Frameworks 路径
        candidates.add(
          '${_parentDir(_parentDir(_parentDir(scriptPath)))}/.env',
        );
      } else if (scriptPath.contains('/Contents/Resources/')) {
        // macOS Resources 路径
        candidates.add('${_parentDir(_parentDir(scriptPath))}/.env');
      }
    } catch (_) {}

    // 2. 从可执行文件路径
    try {
      final execPath = Platform.resolvedExecutable;
      candidates.add('${_parentDir(execPath)}/.env'); // iOS: Runner.app/
      candidates.add(
        '${_parentDir(_parentDir(execPath))}/.env',
      ); // macOS: Runner.app/Contents/
    } catch (_) {}

    // 3. 工作目录
    candidates.add('.env');
    // iOS App Bundle 内（.env 通过 Xcode 添加到 Runner 组）
    try {
      final bundleDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$bundleDir/.env');
      candidates.add('$bundleDir/../.env'); // relative to Runner.app
    } catch (_) {}
    return candidates;
  }

  String _parentDir(String path) => File(path).parent.path;

  Map<String, String> _runtimeCompileTimeEnv() {
    final values = Map<String, String>.from(_compileTimeDefaults);
    final overrides = _testCompileTimeEnv;
    if (overrides != null) {
      for (final key in _configKeys) {
        if (!overrides.containsKey(key)) continue;
        values[key] = overrides[key] ?? '';
      }
    }
    return values;
  }

  void _mergeCompileTimeFallback() {
    final fallback = _runtimeCompileTimeEnv();
    for (final key in _configKeys) {
      if (_isBlockedForCurrentBuild(key)) continue;
      final currentValue = _vars[key]?.trim() ?? '';
      if (currentValue.isEmpty) {
        final value = fallback[key]?.trim() ?? '';
        if (value.isNotEmpty) _vars[key] = value;
      }
    }
  }

  bool _isBlockedForCurrentBuild(String key) {
    final flavor = _testBuildFlavor ?? AppFlavorX.current;
    if (flavor == AppFlavor.cn) return _intlOnlyConfigKeys.contains(key);
    return _cnOnlyConfigKeys.contains(key);
  }

  String _env(String key) {
    if (_isBlockedForCurrentBuild(key)) return '';
    return _vars[key] ?? '';
  }

  /// 通用环境变量读取（给 CloudService 用）
  String env(String key) => _env(key);

  // ——— 阿里云 ———

  String get aliyunAccessKeyId => _env('ALIYUN_ACCESS_KEY_ID');
  String get aliyunAccessKeySecret => _env('ALIYUN_ACCESS_KEY_SECRET');
  String get aliyunAsrAppKey => _env('ALIYUN_ASR_APP_KEY');

  bool get isAliyunConfigured =>
      aliyunAccessKeyId.isNotEmpty && aliyunAccessKeySecret.isNotEmpty;

  // ——— 通义千问 ———

  String get qwenApiKey => _env('QWEN_API_KEY');
  String get ocrSpaceApiKey => _env('OCR_SPACE_API_KEY');
  String get baiduAk => _env('BAIDU_AK');
  String get baiduSk => _env('BAIDU_SK');
  String get geminiApiKey => _env('GEMINI_API_KEY');
  String get googleVisionApiKey => _env('GOOGLE_VISION_API_KEY');
  String get finnhubApiKey => _env('FINNHUB_API_KEY');
  String get zhituApiToken => _env('ZHITU_API_TOKEN');

  bool get isQwenConfigured => qwenApiKey.isNotEmpty;
  bool get isGeminiConfigured => geminiApiKey.isNotEmpty;
  bool get isGoogleVisionConfigured => googleVisionApiKey.isNotEmpty;
  bool get isBaiduOcrConfigured => baiduAk.isNotEmpty && baiduSk.isNotEmpty;
  bool get isFinnhubConfigured => finnhubApiKey.isNotEmpty;
  bool get isZhituConfigured => zhituApiToken.isNotEmpty;

  // ——— 阿里云函数计算 ———

  String get aliyunFCApi => _env('ALIYUN_FC_API');

  bool get isAliyunFCConfigured => aliyunFCApi.isNotEmpty;

  // ——— 国际认证 ———

  String get googleIosClientId => _env('GOOGLE_IOS_CLIENT_ID');
  String get googleServerClientId => _env('GOOGLE_SERVER_CLIENT_ID');
  String get googleIosReversedClientId => _env('GOOGLE_IOS_REVERSED_CLIENT_ID');
  String get googleAndroidClientId => _env('GOOGLE_ANDROID_CLIENT_ID');

  bool get isGoogleSignInConfigured =>
      isGoogleSignInIosConfigured || isGoogleSignInAndroidConfigured;

  bool get isGoogleSignInIosConfigured =>
      googleIosClientId.isNotEmpty ||
      googleIosReversedClientId.isNotEmpty ||
      googleServerClientId.isNotEmpty;

  bool get isGoogleSignInAndroidConfigured =>
      googleServerClientId.isNotEmpty || googleAndroidClientId.isNotEmpty;

  bool get isGoogleSignInIosFullyConfigured =>
      googleIosClientId.isNotEmpty &&
      googleServerClientId.isNotEmpty &&
      googleIosReversedClientId.isNotEmpty;

  bool get isGoogleSignInAndroidFullyConfigured =>
      googleServerClientId.isNotEmpty;

  bool get isGoogleSignInFullyConfigured =>
      isGoogleSignInIosFullyConfigured || isGoogleSignInAndroidFullyConfigured;
}
