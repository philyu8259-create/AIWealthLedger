import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../services/ad_preferences_service.dart';
import '../../../../services/ai_privacy_consent_service.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../../../../services/pangle_ad_service.dart';
import '../../../../services/vip_service.dart';

class HomePangleBannerAd extends StatefulWidget {
  const HomePangleBannerAd({super.key});

  @override
  State<HomePangleBannerAd> createState() => _HomePangleBannerAdState();
}

class _HomePangleBannerAdState extends State<HomePangleBannerAd> {
  final PangleAdConfig _config = PangleAdConfig.homeBanner;
  Future<bool>? _initialization;
  bool? _lastPersonalizedAdsEnabled;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    final adPreferences = getIt<AdPreferencesService>();
    final vipService = getIt<VipService>();
    return ListenableBuilder(
      listenable: Listenable.merge([adPreferences, vipService]),
      builder: (context, _) {
        final hasPrivacyConsent =
            getIt<AIPrivacyConsentService>().hasAppPrivacyConsent;
        final isVip = vipService.isVip;
        final shouldShow = getIt<PangleAdService>().shouldShowHomeBanner(
          flavor: getIt<AppProfileService>().flavor,
          platform: defaultTargetPlatform,
          hasPrivacyConsent: hasPrivacyConsent,
          isVip: isVip,
          config: _config,
        );
        if (!shouldShow) return const SizedBox.shrink();

        final personalizedAdsEnabled = adPreferences.personalizedAdsEnabled;
        if (_initialization == null ||
            _lastPersonalizedAdsEnabled != personalizedAdsEnabled) {
          _lastPersonalizedAdsEnabled = personalizedAdsEnabled;
          _initialization = getIt<PangleAdService>().initialize(
            config: _config,
            personalizedAdsEnabled: personalizedAdsEnabled,
          );
        }

        return FutureBuilder<bool>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(
                    constraints.maxWidth,
                    _config.widthDp.toDouble(),
                  );
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: _config.heightDp.toDouble(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AndroidView(
                          viewType: PangleAdService.viewType,
                          creationParams: _config.toCreationParams(
                            personalizedAdsEnabled: personalizedAdsEnabled,
                          ),
                          creationParamsCodec: const StandardMessageCodec(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
