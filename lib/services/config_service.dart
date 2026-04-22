import 'dart:io';
import 'package:flutter/foundation.dart';

/// 统一配置服务 — 从 .env 读取所有环境变量
/// 不依赖 flutter_dotenv，直接解析文件
class ConfigService {
  static ConfigService? _instance;
  Map<String, String> _vars = {};

  ConfigService._();

  static ConfigService get instance {
    _instance ??= ConfigService._();
    return _instance!;
  }

  bool _loaded = false;

  /// 启动时调用一次
  Future<void> load() async {
    if (_loaded) return;
    _vars = {};

    // 尝试多个路径直到找到 .env
    final candidates = _getEnvCandidates();

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

    _loaded = true;
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

  String _env(String key) => _vars[key] ?? '';

  /// 通用环境变量读取（给 CloudService 用）
  String env(String key) => _vars[key] ?? '';

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

  bool get isQwenConfigured => qwenApiKey.isNotEmpty;
  bool get isGeminiConfigured => geminiApiKey.isNotEmpty;
  bool get isGoogleVisionConfigured => googleVisionApiKey.isNotEmpty;
  bool get isFinnhubConfigured => finnhubApiKey.isNotEmpty;

  // ——— 阿里云函数计算 ———

  String get aliyunFCApi => _env('ALIYUN_FC_API');

  bool get isAliyunFCConfigured => aliyunFCApi.isNotEmpty;

  // ——— 国际认证 ———

  String get googleIosClientId => _env('GOOGLE_IOS_CLIENT_ID');
  String get googleServerClientId => _env('GOOGLE_SERVER_CLIENT_ID');
  String get googleIosReversedClientId =>
      _env('GOOGLE_IOS_REVERSED_CLIENT_ID');

  bool get isGoogleSignInConfigured => googleIosClientId.isNotEmpty;
  bool get isGoogleSignInFullyConfigured =>
      googleIosClientId.isNotEmpty &&
      googleServerClientId.isNotEmpty &&
      googleIosReversedClientId.isNotEmpty;

  // ——— Apple App Store ———

  /// Apple 订阅收据验证密钥（从 App Store Connect 获取）
  String get appStoreSharedSecret => _env('APP_STORE_SHARED_SECRET');

  bool get isAppStoreSecretConfigured => appStoreSharedSecret.isNotEmpty;
}
