import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/injection.dart';
import '../../../../services/intl_auth_service.dart';

class IntlAuthPage extends StatefulWidget {
  const IntlAuthPage({super.key});

  @override
  State<IntlAuthPage> createState() => _IntlAuthPageState();
}

class _IntlAuthPageState extends State<IntlAuthPage> {
  String? _loadingProvider;
  Timer? _demoPressTimer;

  bool get _busy => _loadingProvider != null;

  @override
  void dispose() {
    _cancelDemoPress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back,
              color: Color(0xFF4A47D8),
              size: 20,
            ),
          ),
          onPressed: _busy ? null : () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360 || constraints.maxHeight < 720;
            final isTablet = constraints.maxWidth >= 768;
            final horizontalPadding = isTablet
                ? 40.0
                : (constraints.maxWidth < 380 ? 20.0 : 28.0);
            final maxContentWidth = isTablet ? 560.0 : (constraints.maxWidth > 520 ? 420.0 : constraints.maxWidth);
            final heroSize = compact ? 64.0 : 72.0;
            final titleSize = compact ? 24.0 : 26.0;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: compact ? 8 : 16),
                        Center(
                          child: Column(
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: _busy ? null : (_) => _startDemoPress(),
                                onTapUp: _busy ? null : (_) => _cancelDemoPress(),
                                onTapCancel: _busy ? null : _cancelDemoPress,
                                child: Container(
                                  width: heroSize,
                                  height: heroSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4A47D8).withValues(alpha: 0.18),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.asset(
                                      'assets/icon_brand_primary.png',
                                      width: heroSize,
                                      height: heroSize,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 16 : 20),
                              Text(
                                t.text(AppStringKeys.intlAuthTitle),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A1A),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.text(AppStringKeys.intlAuthSubtitle),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 28 : 40),
                        _AuthButton(
                          icon: Icons.g_mobiledata,
                          label: t.text(AppStringKeys.intlAuthGoogle),
                          loading: _loadingProvider == 'google',
                          onTap: _busy ? null : _signInWithGoogle,
                        ),
                        const SizedBox(height: 12),
                        _AuthButton(
                          icon: Icons.apple,
                          label: t.text(AppStringKeys.intlAuthApple),
                          loading: _loadingProvider == 'apple',
                          onTap: _busy ? null : _signInWithApple,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: t.text(AppStringKeys.phoneLoginAgreementPrefix),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${t.text(AppStringKeys.settingsTermsTitle)} ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A47D8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _openTermsOfService(context),
                                ),
                                TextSpan(
                                  text: t.text(AppStringKeys.phoneLoginAgreementAnd),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${t.text(AppStringKeys.settingsPrivacyTitle)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF4A47D8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _openPrivacyPolicy(context),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: compact ? 24 : 40),
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
    if (_busy || !mounted) return;
    await _performProviderSignIn(
      provider: 'demo',
      action: () => getIt<IntlAuthService>().signInWithIntlDemo(),
    );
  }

  Future<void> _signInWithGoogle() async {
    await _performProviderSignIn(
      provider: 'google',
      action: () => getIt<IntlAuthService>().signInWithGoogle(),
    );
  }

  Future<void> _signInWithApple() async {
    await _performProviderSignIn(
      provider: 'apple',
      action: () => getIt<IntlAuthService>().signInWithApple(),
    );
  }

  Future<void> _performProviderSignIn({
    required String provider,
    required Future<void> Function() action,
  }) async {
    if (_busy) return;
    _cancelDemoPress();
    setState(() => _loadingProvider = provider);

    try {
      await action();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      final t = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.text(
              AppStringKeys.intlAuthLoginFailed,
              params: {'error': '$e'},
            ),
          ),
          backgroundColor: Colors.red.shade400,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingProvider = null);
      }
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
          AppStrings.of(context).text(AppStringKeys.phoneLoginOpenPrivacyFailed),
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
          AppStrings.of(context).text(AppStringKeys.phoneLoginOpenTermsFailed),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );

    final child = loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 16)),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(onPressed: onTap, style: style, child: child),
    );
  }
}
