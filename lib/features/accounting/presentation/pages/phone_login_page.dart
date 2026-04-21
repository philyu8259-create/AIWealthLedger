import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/aliyun_sms_service.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../../../services/injection.dart';
import '../../../../services/stock_service.dart';
import '../../../../services/vip_service.dart';
import '../../data/datasources/i_account_entry_datasource.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _countingDown = false;
  int _countdown = 0;
  bool _sending = false;
  bool _verifying = false;
  String? _phoneError;
  String? _codeError;

  late final AliyunSmsService _smsService;

  @override
  void initState() {
    super.initState();
    _smsService = getIt<AliyunSmsService>();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _openPrivacyPolicy() async {
    final url = Uri.parse(getIt<AppProfileService>().privacyPolicyUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.phoneLoginOpenPrivacyFailed),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openTermsOfService() async {
    final url = Uri.parse(getIt<AppProfileService>().termsOfServiceUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(AppStringKeys.phoneLoginOpenTermsFailed),
            ),
          ),
        );
      }
    }
  }

  void _validatePhone() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _phoneError = null);
      return;
    }
    if (phone.length != 11) {
      setState(
        () => _phoneError = AppStrings.of(context).text(AppStringKeys.phoneLoginInvalidPhone),
      );
    } else {
      setState(() => _phoneError = null);
    }
  }

  void _validateCode() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = null);
      return;
    }
    if (code.length < 4 || code.length > 8) {
      setState(
        () => _codeError = AppStrings.of(context).text(AppStringKeys.phoneLoginInvalidCodeLength),
      );
    } else {
      setState(() => _codeError = null);
    }
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      setState(
        () => _phoneError = AppStrings.of(context).text(AppStringKeys.phoneLoginInvalidPhone),
      );
      return;
    }

    if (_sending || _countingDown) return;
    setState(() => _sending = true);

    try {
      await _smsService.sendCode(phone);
      setState(() {
        _countdown = 60;
        _countingDown = true;
        _sending = false;
      });
      _startCountdown();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(
                AppStringKeys.phoneLoginSendFailed,
                params: {'error': '$e'},
              ),
            ),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      final i = _countdown;
      if (i <= 0) {
        if (mounted) setState(() => _countingDown = false);
        return false;
      }
      if (mounted) setState(() => _countdown = i - 1);
      return true;
    });
  }

  Future<void> _verifyCode() async {
    // validate all fields
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();

    bool hasError = false;
    if (phone.isEmpty || phone.length != 11) {
      setState(
        () => _phoneError = AppStrings.of(context).text(AppStringKeys.phoneLoginInvalidPhone),
      );
      hasError = true;
    }
    if (code.isEmpty || code.length < 4 || code.length > 8) {
      setState(
        () => _codeError = AppStrings.of(context).text(AppStringKeys.phoneLoginInvalidCodeInput),
      );
      hasError = true;
    }
    if (hasError) return;

    setState(() => _verifying = true);

    try {
      // 开发者 bypass：直接过审（无需真实验证码）
      if (phone == '15692162538' ||
          phone == '17512122538' ||
          phone == '15601891127' ||
          phone == '15618231127') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_logged_in', true);
        await prefs.setString('logged_in_phone', phone);
        await prefs.remove('logged_in_email');
        await prefs.setString('logged_in_auth_provider', 'phone');
        await prefs.setString('logged_in_display_name', phone);
        await getIt<AppProfileService>().lockCurrentMode();
        await DemoDataSeeder.clear();
        try {
          await getIt<IAccountEntryDataSource>().restoreFromCloudIfNeeded();
          await getIt<StockService>().restoreFromCloudIfNeeded();
        } catch (e) {
          debugPrint('[PhoneLogin] restoreFromCloudIfNeeded error: $e');
        }
        // 开发者账号登录后恢复购买
        try {
          await getIt<VipService>().restorePurchases();
        } catch (e) {
          debugPrint('[PhoneLogin] dev restorePurchases error: $e');
        }
        // 登录后同步云端 VIP 档案
        try {
          await getIt<VipService>().syncFromCloud();
        } catch (e) {
          debugPrint('[PhoneLogin] dev syncFromCloud error: $e');
        }
        if (mounted) context.go('/home');
        return;
      }
      final valid = await _smsService.verifyCode(phone, code);
      if (!valid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppStrings.of(context).text(AppStringKeys.phoneLoginCodeWrong),
              ),
              backgroundColor: Colors.red.shade400,
            ),
          );
        }
        setState(() => _verifying = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_logged_in', true);
      await prefs.setString('logged_in_phone', phone);
      await prefs.remove('logged_in_email');
      await prefs.setString('logged_in_auth_provider', 'phone');
      await prefs.setString('logged_in_display_name', phone);
      await getIt<AppProfileService>().lockCurrentMode();
      await DemoDataSeeder.clear();
      // 登录后尝试从云端恢复数据（仅当本地为空时）
      try {
        await getIt<IAccountEntryDataSource>().restoreFromCloudIfNeeded();
        await getIt<StockService>().restoreFromCloudIfNeeded();
      } catch (e) {
        debugPrint('[PhoneLogin] restoreFromCloudIfNeeded error: $e');
      }
      // 登录后恢复购买
      try {
        await getIt<VipService>().restorePurchases();
      } catch (e) {
        debugPrint('[PhoneLogin] restorePurchases error: $e');
      }
      // 登录后同步云端 VIP 档案
      try {
        await getIt<VipService>().syncFromCloud();
      } catch (e) {
        debugPrint('[PhoneLogin] syncFromCloud error: $e');
      }
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).text(
                AppStringKeys.phoneLoginLoginFailed,
                params: {'error': '$e'},
              ),
            ),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
      setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

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
          onPressed: () => context.pop(),
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
            final buttonHeight = compact ? 48.0 : 52.0;

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

                        // Logo & Title
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: heroSize,
                                height: heroSize,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF4A47D8), Color(0xFF6D5DF6)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF4A47D8,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet,
                                  color: Colors.white,
                                  size: compact ? 32 : 36,
                                ),
                              ),
                              SizedBox(height: compact ? 16 : 20),
                              Text(
                                strings.text(AppStringKeys.phoneLoginTitle),
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A1A),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                strings.text(AppStringKeys.phoneLoginAutoCreateNotice),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: compact ? 32 : 48),

              // 手机号
              Text(
                strings.text(AppStringKeys.phoneLoginPhoneLabel),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      border: Border.all(
                        color: _phoneError != null
                            ? Colors.red.shade400
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '🇨🇳  +86',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 20,
                          color: const Color(0xFFE5E7EB),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      onChanged: (_) => _validatePhone(),
                      decoration: InputDecoration(
                        hintText: strings.text(AppStringKeys.phoneLoginPhoneHint),
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 15,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          borderSide: BorderSide(
                            color: Color(0xFF4A47D8),
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          borderSide: BorderSide(color: Colors.red.shade400),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          borderSide: BorderSide(
                            color: Colors.red.shade400,
                            width: 1.5,
                          ),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        errorText: _phoneError,
                        errorStyle: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12,
                        ),
                      ),
                      style: const TextStyle(fontSize: 15, letterSpacing: 1),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 验证码
              Text(
                strings.text(AppStringKeys.phoneLoginCodeLabel),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 8,
                onChanged: (_) => _validateCode(),
                decoration: InputDecoration(
                  hintText: strings.text(AppStringKeys.phoneLoginCodeHint),
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _codeError != null
                          ? Colors.red.shade400
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF4A47D8),
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.red.shade400),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  errorText: _codeError,
                  errorStyle: TextStyle(
                    color: Colors.red.shade400,
                    fontSize: 12,
                  ),
                  suffixIcon: _countingDown
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF4A47D8,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_countdown}s',
                              style: const TextStyle(
                                color: Color(0xFF4A47D8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: _phoneError == null ? _sendCode : null,
                          child: Text(
                            _sending
                                ? strings.text(AppStringKeys.phoneLoginSendingCode)
                                : strings.text(AppStringKeys.phoneLoginSendCode),
                            style: TextStyle(
                              color: _phoneError == null
                                  ? const Color(0xFF4A47D8)
                                  : Colors.grey.shade400,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
                style: const TextStyle(fontSize: 15, letterSpacing: 4),
                onSubmitted: (_) => _verifyCode(),
              ),

              const SizedBox(height: 32),

                        // 登录按钮
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: ElevatedButton(
                  onPressed: _verifying ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A47D8),
                    disabledBackgroundColor: const Color(
                      0xFF4A47D8,
                    ).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          strings.text(AppStringKeys.phoneLoginLogin),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                          ),
                        ),

                        SizedBox(height: compact ? 20 : 24),

              // 协议提示
              Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: strings.text(AppStringKeys.phoneLoginAgreementPrefix),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      TextSpan(
                        text: '《${strings.text(AppStringKeys.settingsTermsTitle)}》',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A47D8),
                          fontWeight: FontWeight.w500,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openTermsOfService,
                      ),
                      TextSpan(
                        text: strings.text(AppStringKeys.phoneLoginAgreementAnd),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      TextSpan(
                        text: '《${strings.text(AppStringKeys.settingsPrivacyTitle)}》',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A47D8),
                          fontWeight: FontWeight.w500,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _openPrivacyPolicy,
                      ),
                    ],
                  ),
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
}
