import '../app_flavor.dart';
import 'capability_profile.dart';
import 'locale_profile.dart';

class AppProfile {
  const AppProfile({
    required this.flavor,
    required this.localeProfile,
    required this.capabilityProfile,
  });

  final AppFlavor flavor;
  final LocaleProfile localeProfile;
  final CapabilityProfile capabilityProfile;
}
