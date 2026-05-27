import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppFlavor { cn, intl }

extension AppFlavorX on AppFlavor {
  static const _modeKey = 'app_mode';
  static const _rawBuildFlavor = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: '',
  );

  static bool get hasExplicitBuildFlavor => explicitBuildFlavor != null;

  static AppFlavor? get explicitBuildFlavor =>
      _parseFlavor(_rawBuildFlavor.trim().toLowerCase());

  static AppFlavor get buildFlavor {
    return explicitBuildFlavor ?? AppFlavor.cn;
  }

  static AppFlavor get current {
    final explicitFlavor = explicitBuildFlavor;
    if (explicitFlavor != null) return explicitFlavor;
    final storedFlavor = _storedFlavor;
    if (storedFlavor != null) return storedFlavor;
    return buildFlavor;
  }

  static AppFlavor? get _storedFlavor {
    try {
      if (GetIt.I.isRegistered<SharedPreferences>()) {
        final raw = GetIt.I<SharedPreferences>().getString(_modeKey)?.trim();
        return _parseFlavor(raw?.trim().toLowerCase());
      }
    } catch (_) {
      // Fallback to compile-time build flavor when prefs are unavailable.
    }
    return null;
  }

  static AppFlavor? _parseFlavor(String? raw) {
    switch (raw) {
      case 'cn':
        return AppFlavor.cn;
      case 'intl':
        return AppFlavor.intl;
      default:
        return null;
    }
  }

  bool get isCn => this == AppFlavor.cn;
  bool get isIntl => this == AppFlavor.intl;

  String get name => this == AppFlavor.cn ? 'cn' : 'intl';

  String get privacyPolicyUrl => isIntl
      ? 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html'
      : 'https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy.html';

  String get termsOfServiceUrl => isIntl
      ? 'https://www.apple.com/legal/internet-services/itunes/'
      : 'https://philyu8259-create.github.io/ai-accounting-privacy/eula.html';
}
