import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppFlavor { cn, intl }

extension AppFlavorX on AppFlavor {
  static const _modeKey = 'app_mode';

  static AppFlavor get buildFlavor {
    const raw = String.fromEnvironment('APP_FLAVOR', defaultValue: 'cn');
    return raw == 'intl' ? AppFlavor.intl : AppFlavor.cn;
  }

  static AppFlavor get current {
    try {
      if (GetIt.I.isRegistered<SharedPreferences>()) {
        final raw = GetIt.I<SharedPreferences>().getString(_modeKey)?.trim();
        if (raw == 'cn') return AppFlavor.cn;
        if (raw == 'intl') return AppFlavor.intl;
      }
    } catch (_) {
      // Fall through to build flavor.
    }
    return buildFlavor;
  }

  bool get isCn => this == AppFlavor.cn;
  bool get isIntl => this == AppFlavor.intl;

  String get name => this == AppFlavor.cn ? 'cn' : 'intl';

  String get privacyPolicyUrl => isIntl
      ? 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html'
      : 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy.html';

  String get termsOfServiceUrl => isIntl
      ? 'https://www.apple.com/legal/internet-services/itunes/'
      : 'https://www.apple.com/legal/internet-services/itunes/cn/terms.html';
}
