import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
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
  static const _goalKey = 'onboarding_primary_goal_v1';

  Timer? _demoPressTimer;
  bool _loggingInDemo = false;
  String _selectedGoal = 'daily';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSelectedGoal());
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'onboarding_viewed',
        properties: {'surface': 'welcome'},
      ),
    );
  }

  @override
  void dispose() {
    _cancelDemoPress();
    super.dispose();
  }

  Future<void> _loadSelectedGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getString(_goalKey);
    if (!mounted || goal == null || goal.isEmpty) return;
    setState(() => _selectedGoal = goal);
  }

  Future<void> _setSelectedGoal(String goal) async {
    setState(() => _selectedGoal = goal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalKey, goal);
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'onboarding_goal_selected',
        properties: {'goal': goal},
      ),
    );
  }

  Future<void> _persistSelectedGoal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalKey, _selectedGoal);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final authProviders = getIt<AppProfileService>()
        .currentProfile
        .capabilityProfile
        .authProviders;
    final usesPhoneAuth = authProviders.contains(AuthProviderType.phoneSms);
    final usesAppleAuth = authProviders.contains(AuthProviderType.apple);

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
                        SizedBox(height: compact ? 18 : 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            strings.text(AppStringKeys.welcomeGoalPrompt),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _GoalChoiceChip(
                              label: strings.text(
                                AppStringKeys.welcomeGoalDaily,
                              ),
                              selected: _selectedGoal == 'daily',
                              onTap: () => _setSelectedGoal('daily'),
                            ),
                            _GoalChoiceChip(
                              label: strings.text(
                                AppStringKeys.welcomeGoalBudget,
                              ),
                              selected: _selectedGoal == 'budget',
                              onTap: () => _setSelectedGoal('budget'),
                            ),
                            _GoalChoiceChip(
                              label: strings.text(
                                AppStringKeys.welcomeGoalAssets,
                              ),
                              selected: _selectedGoal == 'assets',
                              onTap: () => _setSelectedGoal('assets'),
                            ),
                            _GoalChoiceChip(
                              label: strings.text(
                                AppStringKeys.welcomeGoalTrend,
                              ),
                              selected: _selectedGoal == 'trend',
                              onTap: () => _setSelectedGoal('trend'),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 24 : 32),
                        if (usesPhoneAuth) ...[
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,
                            child: FilledButton(
                              onPressed: () => _guestLogin(context),
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
                              onPressed: () => context.push('/phone_login'),
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
                              onTap: () => _signInWithApple(context),
                            ),
                          ],
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,
                            child: FilledButton(
                              onPressed: () => _guestLogin(context),
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
                            onTap: () => _signInWithGoogle(context),
                          ),
                          const SizedBox(height: 12),
                          _IntlAuthEntryButton(
                            icon: Icons.apple,
                            label: strings.text(AppStringKeys.intlAuthApple),
                            onTap: () => _signInWithApple(context),
                          ),
                        ],
                        SizedBox(height: compact ? 24 : 32),
                        Text.rich(
                          textAlign: TextAlign.center,
                          TextSpan(
                            children: [
                              TextSpan(
                                text: strings.text(
                                  AppStringKeys.welcomeAgreementPrefix,
                                ),
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
                                text: strings.text(
                                  AppStringKeys.welcomeAgreementAnd,
                                ),
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

  Future<void> _activateDemoMode() async {
    _cancelDemoPress();
    if (_loggingInDemo || !mounted) return;

    setState(() => _loggingInDemo = true);
    try {
      await _persistSelectedGoal();
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
    await prefs.setString(_goalKey, _selectedGoal);
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
      await _persistSelectedGoal();
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
      await _persistSelectedGoal();
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

class _GoalChoiceChip extends StatelessWidget {
  const _GoalChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF4A47D8);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : primary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      selectedColor: primary,
      backgroundColor: primary.withValues(alpha: 0.06),
      side: BorderSide(color: primary.withValues(alpha: selected ? 0.0 : 0.16)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
