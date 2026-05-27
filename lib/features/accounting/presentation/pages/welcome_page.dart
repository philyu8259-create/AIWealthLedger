import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/ai_privacy_consent_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../../../services/funnel_analytics_service.dart';
import '../../../../services/injection.dart';
import '../../../../services/intl_auth_service.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  Timer? _demoPressTimer;
  bool _loggingInDemo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_trackOnboardingAfterPrivacyConsent());
    });
  }

  @override
  void dispose() {
    _cancelDemoPress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isZhLocale = Localizations.localeOf(context).languageCode == 'zh';
    final agreementGap = isZhLocale ? '' : ' ';
    final authProviders = getIt<AppProfileService>()
        .currentProfile
        .capabilityProfile
        .authProviders;
    final usesPhoneAuth = authProviders.contains(AuthProviderType.phoneSms);
    final usesAppleAuth =
        authProviders.contains(AuthProviderType.apple) &&
        supportsAppleSignInOnTargetPlatform(defaultTargetPlatform);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 360 || constraints.maxHeight < 720;
            final isTablet = constraints.maxWidth >= 768;
            final horizontalPadding = isTablet
                ? 40.0
                : (constraints.maxWidth < 380 ? 20.0 : 32.0);
            final maxContentWidth = isTablet
                ? 560.0
                : (constraints.maxWidth > 520 ? 420.0 : constraints.maxWidth);
            final iconSize = compact ? 68.0 : 80.0;
            final titleSize = compact ? 28.0 : 32.0;
            final subtitleSize = compact ? 14.0 : 15.0;
            final buttonHeight = compact ? 48.0 : 52.0;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: compact ? 12 : 24),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: _loggingInDemo
                              ? null
                              : (_) => _startDemoPress(),
                          onTapUp: _loggingInDemo
                              ? null
                              : (_) => _cancelDemoPress(),
                          onTapCancel: _loggingInDemo ? null : _cancelDemoPress,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              'assets/icon_brand_primary.png',
                              width: iconSize,
                              height: iconSize,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 20 : 24),
                        Text(
                          strings.text(AppStringKeys.welcomeTitle),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.text(AppStringKeys.welcomeSubtitle),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: subtitleSize,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: compact ? 16 : 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ValueProofPill(
                              icon: Icons.mic_none_rounded,
                              label: strings.text(
                                AppStringKeys.welcomeValueVoice,
                              ),
                            ),
                            _ValueProofPill(
                              icon: Icons.receipt_long_rounded,
                              label: strings.text(
                                AppStringKeys.welcomeValueReceipt,
                              ),
                            ),
                            _ValueProofPill(
                              icon: Icons.insights_rounded,
                              label: strings.text(
                                AppStringKeys.welcomeValueReview,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 28 : 40),
                        if (usesPhoneAuth) ...[
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,
                            child: FilledButton(
                              onPressed: () => _continueWithPrivacyConsent(
                                context,
                                () => _guestLogin(context),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4A47D8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                strings.text(AppStringKeys.welcomeGuestLogin),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,
                            child: OutlinedButton(
                              onPressed: () => _continueWithPrivacyConsent(
                                context,
                                () async => context.push('/phone_login'),
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                strings.text(AppStringKeys.welcomePhoneLogin),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          if (usesAppleAuth) ...[
                            const SizedBox(height: 12),
                            _IntlAuthEntryButton(
                              icon: Icons.apple,
                              label: strings.text(AppStringKeys.intlAuthApple),
                              onTap: () => _continueWithPrivacyConsent(
                                context,
                                () => _signInWithApple(context),
                              ),
                            ),
                          ],
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,
                            child: FilledButton(
                              onPressed: () => _continueWithPrivacyConsent(
                                context,
                                () => _guestLogin(context),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4A47D8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                strings.text(AppStringKeys.welcomeGuestLogin),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _IntlAuthEntryButton(
                            icon: Icons.g_mobiledata,
                            label: strings.text(AppStringKeys.intlAuthGoogle),
                            onTap: () => _continueWithPrivacyConsent(
                              context,
                              () => _signInWithGoogle(context),
                            ),
                          ),
                          if (usesAppleAuth) ...[
                            const SizedBox(height: 12),
                            _IntlAuthEntryButton(
                              icon: Icons.apple,
                              label: strings.text(AppStringKeys.intlAuthApple),
                              onTap: () => _continueWithPrivacyConsent(
                                context,
                                () => _signInWithApple(context),
                              ),
                            ),
                          ],
                        ],
                        SizedBox(height: compact ? 24 : 32),
                        Text.rich(
                          textAlign: TextAlign.center,
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${strings.text(AppStringKeys.welcomeAgreementPrefix)}$agreementGap',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              TextSpan(
                                text: _docLinkTitle(
                                  context,
                                  strings.text(
                                    AppStringKeys.settingsTermsTitle,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4A47D8),
                                  fontWeight: FontWeight.w500,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openTermsOfService(context),
                              ),
                              TextSpan(
                                text: isZhLocale
                                    ? strings.text(
                                        AppStringKeys.welcomeAgreementAnd,
                                      )
                                    : ' ${strings.text(AppStringKeys.welcomeAgreementAnd)} ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              TextSpan(
                                text: _docLinkTitle(
                                  context,
                                  strings.text(
                                    AppStringKeys.settingsPrivacyTitle,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF4A47D8),
                                  fontWeight: FontWeight.w500,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openPrivacyPolicy(context),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 16 : 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _startDemoPress() {
    _cancelDemoPress();
    _demoPressTimer = Timer(const Duration(seconds: 3), () {
      _activateDemoMode();
    });
  }

  void _cancelDemoPress() {
    _demoPressTimer?.cancel();
    _demoPressTimer = null;
  }

  Future<void> _trackOnboardingAfterPrivacyConsent() async {
    if (!mounted) return;
    final consent = getIt<AIPrivacyConsentService>();
    if (!consent.hasAppPrivacyConsent) {
      final accepted = await _showAppPrivacyConsentDialog(context);
      if (!accepted || !mounted) return;
    }
    await _trackOnboardingViewed();
  }

  Future<void> _trackOnboardingViewed() async {
    await getIt<FunnelAnalyticsService>().track(
      'onboarding_viewed',
      properties: {'surface': 'welcome'},
    );
  }

  Future<void> _continueWithPrivacyConsent(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    if (!await _ensureAppPrivacyConsent(context)) return;
    await action();
  }

  Future<bool> _ensureAppPrivacyConsent(BuildContext context) async {
    final consent = getIt<AIPrivacyConsentService>();
    if (consent.hasAppPrivacyConsent) return true;

    final accepted = await _showAppPrivacyConsentDialog(context);
    if (accepted) return true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).text(AppStringKeys.welcomePrivacyGateRequired),
          ),
        ),
      );
    }
    return false;
  }

  Future<bool> _showAppPrivacyConsentDialog(BuildContext context) async {
    final strings = AppStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.text(AppStringKeys.welcomePrivacyGateTitle)),
        content: Text(strings.text(AppStringKeys.welcomePrivacyGateContent)),
        actions: [
          TextButton(
            onPressed: () => _openTermsOfService(dialogContext),
            child: Text(strings.text(AppStringKeys.settingsTermsTitle)),
          ),
          TextButton(
            onPressed: () => _openPrivacyPolicy(dialogContext),
            child: Text(strings.text(AppStringKeys.settingsPrivacyTitle)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.text(AppStringKeys.welcomePrivacyGateDecline)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.text(AppStringKeys.welcomePrivacyGateAgree)),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await getIt<AIPrivacyConsentService>().setAppPrivacyConsent();
      return true;
    }
    return false;
  }

  Future<void> _activateDemoMode() async {
    _cancelDemoPress();
    if (_loggingInDemo || !mounted) return;
    if (!await _ensureAppPrivacyConsent(context)) return;

    setState(() => _loggingInDemo = true);
    try {
      final authProviders = getIt<AppProfileService>()
          .currentProfile
          .capabilityProfile
          .authProviders;
      final usesPhoneAuth = authProviders.contains(AuthProviderType.phoneSms);

      if (usesPhoneAuth) {
        await DemoDataSeeder.seed(variant: DemoDataVariant.cn);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_logged_in', true);
        await prefs.setString('logged_in_phone', 'DemoAccount');
        await prefs.remove('logged_in_email');
        await prefs.setString('logged_in_auth_provider', 'demo');
        await prefs.setString('logged_in_display_name', 'DemoAccount');
        await getIt<AppProfileService>().lockCurrentMode();
      } else {
        await getIt<IntlAuthService>().signInWithIntlDemo();
      }

      if (!mounted) return;
      unawaited(
        getIt<FunnelAnalyticsService>().track(
          'onboarding_completed',
          properties: {'method': 'demo'},
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.text(
              AppStringKeys.intlAuthLoginFailed,
              params: {'error': '$e'},
            ),
          ),
          backgroundColor: Colors.red.shade400,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loggingInDemo = false);
      }
    }
  }

  Future<void> _guestLogin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_logged_in', true);
    await prefs.remove('logged_in_phone');
    await prefs.remove('logged_in_email');
    await prefs.setString('logged_in_auth_provider', 'guest');
    await prefs.remove('logged_in_display_name');
    await getIt<AppProfileService>().lockCurrentMode();
    if (!context.mounted) return;
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'onboarding_completed',
        properties: {'method': 'guest'},
      ),
    );
    context.go('/home');
  }

  String _docLinkTitle(BuildContext context, String title) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'zh' ? '《$title》' : title;
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      await getIt<IntlAuthService>().signInWithGoogle();
      if (!context.mounted) return;
      unawaited(
        getIt<FunnelAnalyticsService>().track(
          'onboarding_completed',
          properties: {'method': 'google'},
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!context.mounted) return;
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.text(
              AppStringKeys.intlAuthLoginFailed,
              params: {'error': '$e'},
            ),
          ),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  Future<void> _signInWithApple(BuildContext context) async {
    try {
      await getIt<IntlAuthService>().signInWithApple();
      if (!context.mounted) return;
      unawaited(
        getIt<FunnelAnalyticsService>().track(
          'onboarding_completed',
          properties: {'method': 'apple'},
        ),
      );
      context.go('/home');
    } catch (e) {
      if (!context.mounted) return;
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.text(
              AppStringKeys.intlAuthLoginFailed,
              params: {'error': '$e'},
            ),
          ),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final url = Uri.parse(getIt<AppProfileService>().privacyPolicyUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context).text(AppStringKeys.welcomeOpenPrivacyFailed),
        ),
      ),
    );
  }

  Future<void> _openTermsOfService(BuildContext context) async {
    final url = Uri.parse(getIt<AppProfileService>().termsOfServiceUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context).text(AppStringKeys.welcomeOpenTermsFailed),
        ),
      ),
    );
  }
}

class _ValueProofPill extends StatelessWidget {
  const _ValueProofPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF4A47D8).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF4A47D8).withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF4A47D8)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4A47D8),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntlAuthEntryButton extends StatelessWidget {
  const _IntlAuthEntryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 16)),
      ],
    );

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      ),
    );
  }
}
