import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/app_flavor.dart';

class PangleAdConfig {
  const PangleAdConfig({
    required this.appId,
    required this.codeId,
    required this.widthDp,
    required this.heightDp,
  });

  static const homeBanner = PangleAdConfig(
    appId: '5827353',
    codeId: '104073039',
    widthDp: 300,
    heightDp: 150,
  );

  final String appId;
  final String codeId;
  final int widthDp;
  final int heightDp;

  bool get isUsable => appId.isNotEmpty && codeId.isNotEmpty;

  Map<String, Object> toCreationParams({required bool personalizedAdsEnabled}) {
    return {
      'appId': appId,
      'codeId': codeId,
      'widthDp': widthDp,
      'heightDp': heightDp,
      'personalizedAdsEnabled': personalizedAdsEnabled,
    };
  }
}

class PangleAdService {
  const PangleAdService({
    MethodChannel channel = const MethodChannel('com.aiaccounting/pangle_ads'),
  }) : _channel = channel;

  static const viewType = 'com.aiaccounting/pangle_banner';

  final MethodChannel _channel;

  bool shouldShowHomeBanner({
    AppFlavor? flavor,
    TargetPlatform? platform,
    required bool hasPrivacyConsent,
    required bool isVip,
    PangleAdConfig config = PangleAdConfig.homeBanner,
  }) {
    final effectiveFlavor = flavor ?? AppFlavorX.current;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return effectiveFlavor == AppFlavor.cn &&
        effectivePlatform == TargetPlatform.android &&
        hasPrivacyConsent &&
        !isVip &&
        config.isUsable;
  }

  Future<bool> initialize({
    PangleAdConfig config = PangleAdConfig.homeBanner,
    required bool personalizedAdsEnabled,
  }) async {
    if (!config.isUsable || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final initialized = await _channel.invokeMethod<bool>('initialize', {
        'appId': config.appId,
        'appName': '财富记账本',
        'personalizedAdsEnabled': personalizedAdsEnabled,
      });
      return initialized ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('[PangleAdService] initialize failed: ${error.message}');
      return false;
    }
  }
}
