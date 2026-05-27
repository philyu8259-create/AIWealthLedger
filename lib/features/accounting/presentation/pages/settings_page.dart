import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import '../../../../app/app_flavor.dart';
import '../../../../app/profile/capability_profile.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/injection.dart';
import '../../../../services/ai_privacy_consent_service.dart';
import '../../../../services/ad_preferences_service.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/aliyun_sms_service.dart';
import '../../../../services/quick_chip_service.dart';
import '../../../../services/cloud_service.dart';
import '../../../../services/avatar_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../../../services/funnel_analytics_service.dart';
import '../../../../services/theme_mode_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/custom_category/custom_category.dart';
import '../bloc/custom_category/custom_category_bloc.dart';
import '../bloc/custom_category/custom_category_event.dart';
import '../bloc/custom_category/custom_category_state.dart';
import '../../../../services/vip_service.dart';
import '../../../../services/stock_service.dart';
import '../widgets/avatar_widgets.dart';
import '../widgets/premium_page_chrome.dart';
import '../widgets/premium_vip_card.dart';
import '../widgets/press_feedback.dart';
import '../widgets/textured_scaffold_background.dart';

Locale _settingsLocale() => getIt<AppProfileService>().currentLocale;

String _settingsShortDate(DateTime date) {
  return AppFormatter.formatShortDate(date, locale: _settingsLocale());
}

String _settingsShortDateTime(DateTime date) {
  return AppFormatter.formatShortDateTime(date, locale: _settingsLocale());
}

String _settingsMoney(
  num amount, {
  String? currencyCode,
  int decimalDigits = 0,
}) {
  final locale = _settingsLocale();
  final effectiveCurrency =
      currencyCode ?? getIt<AppProfileService>().currentBaseCurrency;
  final symbol = AppFormatter.currencySymbol(
    currencyCode: effectiveCurrency,
    locale: locale,
  );
  final number = AppFormatter.formatDecimal(
    amount,
    locale: locale,
    decimalDigits: decimalDigits,
  );
  return '$symbol$number';
}

String _settingsAiProviderLabel(AppStrings t) {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.aiProvider;
  switch (provider) {
    case AiProviderType.gemini:
      return t.text(AppStringKeys.providerAiGemini);
    case AiProviderType.legacyCnAi:
      return t.text(AppStringKeys.providerAiQwen);
  }
}

String _settingsOcrProviderLabel(AppStrings t) {
  final provider =
      getIt<AppProfileService>().currentProfile.capabilityProfile.ocrProvider;
  switch (provider) {
    case OcrProviderType.googleVisionGemini:
    case OcrProviderType.googleExpenseParser:
      return t.text(AppStringKeys.providerOcrGoogleVision);
    case OcrProviderType.legacyCnOcr:
      return t.text(AppStringKeys.providerOcrBaidu);
  }
}

String _settingsThemeModeLabel(
  BuildContext context,
  AppThemePreference preference,
) {
  final t = AppStrings.of(context);
  switch (preference) {
    case AppThemePreference.light:
      return t.text(AppStringKeys.settingsThemeModeLightLabel);
    case AppThemePreference.dark:
      return t.text(AppStringKeys.settingsThemeModeDarkLabel);
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoggedIn = false;
  bool _canDeleteAccount = false;
  String _userDisplayName = AppStrings.forLocale(
    getIt<AppProfileService>().currentLocale,
  ).text(AppStringKeys.settingsGuestUser);
  String _appVersion = '1.0.1';
  final GlobalKey _exportListTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadAppVersion();
    unawaited(getIt<VipService>().syncFromCloud());
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('has_logged_in') ?? false;
    final accountKey = prefs.getString('logged_in_phone') ?? '';
    final displayName = prefs.getString('logged_in_display_name') ?? '';
    final email = prefs.getString('logged_in_email') ?? '';
    setState(() {
      _isLoggedIn = loggedIn && accountKey.isNotEmpty;
      _canDeleteAccount = _isLoggedIn;
      if (_isLoggedIn) {
        final preferredName = displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty ? email : accountKey);
        if (preferredName.length == 11) {
          _userDisplayName =
              '${preferredName.substring(0, 3)}****${preferredName.substring(7)}';
        } else {
          _userDisplayName = preferredName;
        }
      } else {
        _userDisplayName = AppStrings.forLocale(
          getIt<AppProfileService>().currentLocale,
        ).text(AppStringKeys.settingsGuestUser);
      }
    });
  }

  void _goToPhoneLogin() {
    context.push('/phone_login');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final subscriptionsEnabled = getIt<AppProfileService>()
        .currentProfile
        .capabilityProfile
        .isEnabled('subscriptions');
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PremiumPageAppBar(title: t.text(AppStringKeys.settingsTitle)),
      body: TexturedScaffoldBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 768;
            final horizontalPadding = isTablet
                ? 24.0
                : (constraints.maxWidth > 520 ? 16.0 : 0.0);
            final maxContentWidth = isTablet
                ? (constraints.maxWidth >= 1024 ? 860.0 : 720.0)
                : (constraints.maxWidth > 560 ? 520.0 : constraints.maxWidth);

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    MediaQuery.of(context).padding.bottom + 120,
                  ),
                  children: [
                    if (subscriptionsEnabled) ...[
                      // 会员专属卡片（页面最顶部）
                      _VipBanner(),
                      const SizedBox(height: 16),
                    ],

                    // 用户信息（带自定义头像）
                    AvatarTile(
                      displayName: _userDisplayName,
                      appVersion: 'v$_appVersion',
                      isLoggedIn: _isLoggedIn,
                      onTap: _isLoggedIn ? null : _goToPhoneLogin,
                    ),

                    _SectionDivider(),
                    _SectionHeader(t.text(AppStringKeys.settingsAccount)),

                    _SettingTile(
                      icon: Icons.category_outlined,
                      title: t.text(
                        AppStringKeys.settingsCustomCategoriesTitle,
                      ),
                      subtitle: t.text(
                        AppStringKeys.settingsCustomCategoriesSubtitle,
                      ),
                      onTap: () => _openCategoryManager(context),
                    ),
                    _SettingTile(
                      icon: Icons.smart_toy_outlined,
                      title: t.text(
                        AppStringKeys.settingsAiConsentWithdrawTitle,
                      ),
                      subtitle: t.text(
                        AppStringKeys.settingsAiConsentWithdrawSubtitle,
                      ),
                      onTap: () => _showWithdrawAIConsentDialog(context),
                    ),
                    _SettingTile(
                      icon: Icons.auto_awesome_motion_outlined,
                      title: t.text(AppStringKeys.settingsAutoBookkeepingTitle),
                      subtitle: t.text(
                        Theme.of(context).platform == TargetPlatform.android
                            ? AppStringKeys
                                  .settingsAutoBookkeepingSubtitleAndroid
                            : AppStringKeys.settingsAutoBookkeepingSubtitle,
                      ),
                      onTap: () => context.push('/auto_bookkeeping'),
                    ),
                    if (_isLoggedIn)
                      _SettingTile(
                        icon: Icons.logout_rounded,
                        title: t.text(AppStringKeys.settingsLogoutTitle),
                        subtitle: t.text(AppStringKeys.settingsLogoutSubtitle),
                        onTap: () => _showLogoutDialog(context),
                      ),
                    if (_canDeleteAccount)
                      _SettingTile(
                        icon: Icons.dangerous_outlined,
                        title: t.text(AppStringKeys.settingsDeleteAccountTitle),
                        titleColor: const Color(0xFFF56C6C),
                        subtitle: t.text(
                          AppStringKeys.settingsDeleteAccountSubtitle,
                        ),
                        onTap: () => _showDeleteAccountDialog(context),
                      ),

                    _SectionDivider(),
                    _SectionHeader(t.text(AppStringKeys.settingsAppearance)),

                    ListenableBuilder(
                      listenable: getIt<ThemeModeService>(),
                      builder: (context, _) {
                        final themeModeService = getIt<ThemeModeService>();
                        return _SettingTile(
                          icon: Icons.contrast_outlined,
                          title: t.text(AppStringKeys.settingsThemeModeTitle),
                          subtitle: t.text(
                            AppStringKeys.settingsThemeModeSubtitle,
                            params: {
                              'current': _settingsThemeModeLabel(
                                context,
                                themeModeService.preference,
                              ),
                            },
                          ),
                          onTap: () => _showThemeModeSheet(context),
                        );
                      },
                    ),

                    _SectionDivider(),
                    _SectionHeader(t.text(AppStringKeys.settingsData)),

                    _SettingTile(
                      icon: Icons.cloud_upload_outlined,
                      title: t.text(AppStringKeys.settingsBackupTitle),
                      subtitle: t.text(AppStringKeys.settingsBackupSubtitle),
                      onTap: () => _doBackup(context),
                    ),
                    _SettingTile(
                      key: _exportListTileKey,
                      icon: Icons.download_outlined,
                      title: t.text(AppStringKeys.settingsExportTitle),
                      subtitle: t.text(AppStringKeys.settingsExportSubtitle),
                      onTap: () => _exportData(context),
                    ),
                    if (Theme.of(context).platform == TargetPlatform.iOS)
                      _SettingTile(
                        icon: Icons.query_stats_rounded,
                        title: t.text(AppStringKeys.settingsFunnelTitle),
                        subtitle: t.text(AppStringKeys.settingsFunnelSubtitle),
                        onTap: () => _openFunnelDiagnostics(context),
                      ),

                    _SectionDivider(),
                    _SectionHeader(t.text(AppStringKeys.settingsAbout)),

                    _SettingTile(
                      icon: Icons.privacy_tip_outlined,
                      title: t.text(AppStringKeys.settingsPrivacyTitle),
                      onTap: () => _openPrivacyPolicy(context),
                    ),
                    if (getIt<AppProfileService>().flavor == AppFlavor.cn)
                      ListenableBuilder(
                        listenable: getIt<AdPreferencesService>(),
                        builder: (context, _) {
                          final service = getIt<AdPreferencesService>();
                          return _SettingSwitchTile(
                            icon: Icons.campaign_outlined,
                            title: t.text(
                              AppStringKeys.settingsPersonalizedAdsTitle,
                            ),
                            subtitle: t.text(
                              service.personalizedAdsEnabled
                                  ? AppStringKeys
                                        .settingsPersonalizedAdsSubtitleOn
                                  : AppStringKeys
                                        .settingsPersonalizedAdsSubtitleOff,
                            ),
                            value: service.personalizedAdsEnabled,
                            onChanged: service.setPersonalizedAdsEnabled,
                          );
                        },
                      ),
                    _SettingTile(
                      icon: Icons.description_outlined,
                      title: t.text(AppStringKeys.settingsTermsTitle),
                      onTap: () => _openTermsOfService(context),
                    ),
                    _SettingTile(
                      icon: Icons.star_outlined,
                      title: t.text(AppStringKeys.settingsRateTitle),
                      onTap: () => _rateApp(context),
                    ),
                    _SettingTile(
                      icon: Icons.info_outline,
                      title: t.text(AppStringKeys.settingsAboutAppTitle),
                      onTap: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _doBackup(BuildContext context) async {
    final t = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.text(AppStringKeys.settingsBackupProgress)),
        duration: const Duration(seconds: 10),
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('logged_in_phone');

      // 已登录用户（手机号）：从本地读取，备份到云端
      // 注意：云端数据无手机号隔离，不读云端覆盖本地
      if (phone != null && phone.isNotEmpty && phone != 'DemoAccount') {
        final jsonStr = prefs.getString('account_entries');
        if (jsonStr == null || jsonStr.isEmpty) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(t.text(AppStringKeys.settingsBackupNoLocalData)),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        final decoded = jsonDecode(jsonStr) as List;
        // 只同步 pending 状态的条目
        int successCount = 0;
        int failedCount = 0;
        final updatedEntries = <Map<String, dynamic>>[];
        for (final e in decoded) {
          final entry = AccountEntry.fromJson(
            Map<String, dynamic>.from(e as Map),
          );
          // 只上传 pending 条目
          if (entry.syncStatus != SyncStatus.pending) {
            updatedEntries.add(e as Map<String, dynamic>);
            continue;
          }
          try {
            final result = await CloudService().addEntry(entry);
            if (result != null) {
              successCount++;
              updatedEntries.add({
                ...e as Map<String, dynamic>,
                'syncStatus': 'synced',
              });
            } else {
              failedCount++;
              updatedEntries.add({
                ...e as Map<String, dynamic>,
                'syncStatus': 'failed',
              });
            }
          } catch (_) {
            failedCount++;
            updatedEntries.add({
              ...e as Map<String, dynamic>,
              'syncStatus': 'failed',
            });
          }
        }
        // 更新本地存储的同步状态
        await prefs.setString('account_entries', jsonEncode(updatedEntries));
        messenger.hideCurrentSnackBar();
        if (failedCount == 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                t.text(
                  AppStringKeys.settingsBackupSuccess,
                  params: {'count': '$successCount'},
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                t.text(
                  AppStringKeys.settingsBackupPartial,
                  params: {
                    'success': '$successCount',
                    'failed': '$failedCount',
                  },
                ),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 游客或 Demo：读云端覆盖本地
      final cloudService = CloudService();
      final entries = await cloudService.getEntries();
      // 强制覆盖本地缓存，确保和云端一致
      final jsonList = entries
          .map(
            (e) => {
              'id': e['id'],
              'type': e['type'],
              'amount': e['amount'],
              'category': e['category'],
              'description': e['description'],
              'date': e['date'] is String
                  ? DateTime.parse(e['date'] as String).millisecondsSinceEpoch
                  : e['date'],
              'createdAt': e['createdAt'] is String
                  ? DateTime.parse(
                      e['createdAt'] as String,
                    ).millisecondsSinceEpoch
                  : e['createdAt'],
              'syncStatus': 'synced',
            },
          )
          .toList();
      await prefs.setString('account_entries', jsonEncode(jsonList));
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.text(
              AppStringKeys.settingsBackupSuccess,
              params: {'count': '${entries.length}'},
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.text(AppStringKeys.settingsBackupFailed, params: {'error': '$e'}),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openCategoryManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) =>
            _CategoryManagerSheet(scrollController: scrollController),
      ),
    );
  }

  Future<void> _showThemeModeSheet(BuildContext context) async {
    final service = getIt<ThemeModeService>();
    final selected = await showModalBottomSheet<AppThemePreference>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ThemeModeSheet(currentPreference: service.preference),
    );
    if (selected == null) return;
    await service.setPreference(selected);
  }

  Future<void> _exportData(BuildContext context) async {
    final t = AppStrings.of(context);
    // 同步获取按钮位置锚点（在任何 async 之前，iPad 需要精确位置）
    final box =
        _exportListTileKey.currentContext?.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    // 先弹出日期范围选择
    final range = await showModalBottomSheet<DateTimeRange>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ExportDateRangeSheet(initialRange: null),
    );
    if (range == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    // 显示加载中
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.text(AppStringKeys.settingsExportProgress)),
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      // 优先读本地存储，Demo 账号数据存在 demo_accounting_entries
      var raw = prefs.getString('account_entries');
      final phone = prefs.getString('logged_in_phone');
      if ((raw == null || raw.isEmpty) && phone == 'DemoAccount') {
        raw = prefs.getString('demo_accounting_entries');
      }
      if (raw == null || raw.isEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(t.text(AppStringKeys.settingsExportNoData))),
        );
        return;
      }

      final List<dynamic> allEntries = jsonDecode(raw);

      // 按日期筛选（date 在 JSON 里存的是 millisecondsSinceEpoch）
      final startMs = range.start.millisecondsSinceEpoch;
      final endMs = range.end.millisecondsSinceEpoch + 86399000;
      final filtered = allEntries.where((e) {
        final d = _parseDateTime(e['date']);
        if (d == null) return false;
        final m = d.millisecondsSinceEpoch;
        return m >= startMs && m <= endMs;
      }).toList();

      if (filtered.isEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(t.text(AppStringKeys.settingsExportNoDataInRange)),
          ),
        );
        return;
      }

      // 生成 CSV（完整字段）
      final buffer = StringBuffer();
      buffer.writeln(t.text(AppStringKeys.settingsExportCsvHeaders));
      final dateFormat = DateFormat('yyyy-MM-dd');
      final timeFormat = DateFormat('HH:mm');

      for (int i = 0; i < filtered.length; i++) {
        final e = filtered[i];
        final type = e['type'] == 'income'
            ? t.text(AppStringKeys.settingsExportCsvTypeIncome)
            : t.text(AppStringKeys.settingsExportCsvTypeExpense);
        final category = '${e['category'] ?? ''}';
        final amount = '${e['amount'] ?? 0}';
        final desc = _escapeCsv('${e['description'] ?? ''}');
        final assetId = '${e['assetId'] ?? ''}';
        final syncStatus = '${e['syncStatus'] ?? ''}';
        final d = _parseDateTime(e['date']) ?? DateTime.now();
        final dateStr = dateFormat.format(d);
        final timeStr = timeFormat.format(d);
        buffer.writeln(
          '${i + 1},$dateStr,$timeStr,$type,$category,$amount,$desc,$assetId,$syncStatus',
        );
      }

      // 写入临时 CSV 文件
      final dir = await getTemporaryDirectory();
      final startStr = dateFormat.format(range.start).replaceAll('-', '');
      final endStr = dateFormat.format(range.end).replaceAll('-', '');
      final fileName =
          '${t.text(AppStringKeys.settingsExportFilePrefix)}_${startStr}_$endStr.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString(), encoding: const Utf8Codec());

      messenger.hideCurrentSnackBar();

      // 分享文件（iPad 需要 sharePositionOrigin，iPhone 自适应）
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: t.text(AppStringKeys.settingsExportSubject),
        text: t.text(
          AppStringKeys.settingsExportMessage,
          params: {
            'start': dateFormat.format(range.start),
            'end': dateFormat.format(range.end),
          },
        ),
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.text(AppStringKeys.settingsExportFailed, params: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  void _openFunnelDiagnostics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _FunnelDiagnosticsSheet(),
    );
  }

  /// 解析日期，支持 int (millisecondsSinceEpoch) 或 String (ISO 8601)
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _escapeCsv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final t = AppStrings.of(context);
    final url = Uri.parse(getIt<AppProfileService>().privacyPolicyUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t.text(AppStringKeys.settingsOpenPrivacyFailed)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                AppStringKeys.settingsOpenLinkFailed,
                params: {'error': '$e'},
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openTermsOfService(BuildContext context) async {
    final t = AppStrings.of(context);
    final url = Uri.parse(getIt<AppProfileService>().termsOfServiceUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t.text(AppStringKeys.settingsOpenTermsFailed)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t.text(
                AppStringKeys.settingsOpenLinkFailed,
                params: {'error': '$e'},
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showWithdrawAIConsentDialog(BuildContext context) async {
    final t = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          title: Text(t.text(AppStringKeys.settingsWithdrawDialogTitle)),
          content: Text(t.text(AppStringKeys.settingsWithdrawDialogContent)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.text(AppStringKeys.commonCancel)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.text(AppStringKeys.settingsWithdrawConfirm)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await getIt<AIPrivacyConsentService>().clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.text(AppStringKeys.settingsWithdrawSuccess)),
          ),
        );
      }
    }
  }

  Future<void> _clearLocalSignedInData(SharedPreferences prefs) async {
    await getIt<VipService>().clearCurrentUserVipCache();
    await getIt<StockService>().clearLocalData();
    await getIt<AvatarService>().clearAvatar();
    await getIt<AIPrivacyConsentService>().clearAll();
    await prefs.remove('has_logged_in');
    await prefs.remove('logged_in_phone');
    await prefs.remove('logged_in_email');
    await prefs.remove('logged_in_auth_provider');
    await prefs.remove('logged_in_display_name');
    await prefs.remove('account_entries');
    await prefs.remove('demo_accounting_entries');
    await prefs.remove('custom_categories');
    await prefs.remove('quick_chip_ids');
    await prefs.remove('quick_chip_service_ids');

    final extraKeys = prefs.getKeys().where(
      (key) =>
          key == 'cloud_assets' ||
          key == 'demo_asset_accounts' ||
          key == 'assets' ||
          key == 'demo_budgets' ||
          key == 'stock_search_cache_v1' ||
          key == 'stock_search_cache_updated_at_v1' ||
          key == 'stock_last_quote_refresh_ms_v1' ||
          key == 'stock_last_manual_refresh_ms_v1' ||
          key == 'stock_last_auto_slot_v1' ||
          key.startsWith('cloud_assets_v2_') ||
          key.startsWith('stock_positions_v2_') ||
          key.startsWith('stock_deleted_ids_v1_'),
    );
    for (final key in extraKeys) {
      await prefs.remove(key);
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final t = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          title: Text(t.text(AppStringKeys.settingsLogoutDialogTitle)),
          content: Text(t.text(AppStringKeys.settingsLogoutDialogContent)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.text(AppStringKeys.settingsLogoutConfirm)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearLocalSignedInData(prefs);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.text(AppStringKeys.settingsLogoutSuccess))),
      );
      context.go('/welcome');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t.text(AppStringKeys.settingsLogoutFailed, params: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  /// 注销账号流程：确认 → 注销云端账号 → 清本地 → 跳转欢迎页
  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final t = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          title: Text(t.text(AppStringKeys.settingsDeleteAccountTitle)),
          content: Text(t.text(AppStringKeys.settingsDeleteDialogContent)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.text(AppStringKeys.commonCancel)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(t.text(AppStringKeys.settingsDeleteConfirmAction)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    // 获取当前登录账号标识
    final prefs = await SharedPreferences.getInstance();
    final accountKey = prefs.getString('logged_in_phone');
    final authProvider = prefs.getString('logged_in_auth_provider') ?? 'phone';
    if (accountKey == null || accountKey.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.text(AppStringKeys.settingsDeleteOnlyLoggedIn)),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.text(AppStringKeys.settingsDeleteProgress)),
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      if (authProvider == 'phone') {
        final sms = AliyunSmsService();

        try {
          await sms.sendCode(accountKey);
        } catch (e) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                t.text(
                  AppStringKeys.settingsDeleteSendCodeFailed,
                  params: {'error': '$e'},
                ),
              ),
            ),
          );
          return;
        }

        if (!context.mounted) return;

        final code = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _SmsCodeInputDialog(phone: accountKey),
        );

        if (code == null || code.isEmpty) {
          messenger.hideCurrentSnackBar();
          return;
        }

        final valid = await sms.verifyCode(accountKey, code);
        if (!valid) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(t.text(AppStringKeys.settingsDeleteCodeWrong)),
            ),
          );
          return;
        }
      }

      if (accountKey == 'DemoAccount') {
        await DemoDataSeeder.clear();
      } else {
        final success = await CloudService().delete('/account');
        if (!success) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(t.text(AppStringKeys.settingsDeleteRequestFailed)),
            ),
          );
          return;
        }
      }

      await _clearLocalSignedInData(prefs);

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(t.text(AppStringKeys.settingsDeleteSuccess))),
      );

      if (!context.mounted) return;
      context.go('/welcome');
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t.text(AppStringKeys.settingsDeleteFailed, params: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  Future<void> _rateApp(BuildContext context) async {
    final t = AppStrings.of(context);
    if (Theme.of(context).platform == TargetPlatform.android) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.text(AppStringKeys.settingsRateUnavailableAndroid)),
        ),
      );
      return;
    }

    final url = Uri.parse(
      'https://apps.apple.com/app/id6761321533?action=write-review',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.text(AppStringKeys.settingsRateOpenFailed))),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          title: Text(t.text(AppStringKeys.settingsAboutAppTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.text(
                  AppStringKeys.settingsAboutVersion,
                  params: {'version': _appVersion},
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(t.text(AppStringKeys.settingsAboutTechStack)),
              const SizedBox(height: 8),
              Text(
                t.text(
                  AppStringKeys.settingsAboutAiServices,
                  params: {
                    'aiProvider': _settingsAiProviderLabel(t),
                    'ocrProvider': _settingsOcrProviderLabel(t),
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(t.text(AppStringKeys.settingsAboutStorage)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: Text(t.text(AppStringKeys.commonClose)),
            ),
          ],
        );
      },
    );
  }
}

class _FunnelDiagnosticsSheet extends StatefulWidget {
  const _FunnelDiagnosticsSheet();

  @override
  State<_FunnelDiagnosticsSheet> createState() =>
      _FunnelDiagnosticsSheetState();
}

class _FunnelDiagnosticsSheetState extends State<_FunnelDiagnosticsSheet> {
  bool _refreshingAttribution = false;
  bool _exporting = false;

  FunnelAnalyticsService get _service => getIt<FunnelAnalyticsService>();

  Future<void> _refreshAttribution() async {
    setState(() => _refreshingAttribution = true);
    await _service.refreshAttributionContext();
    if (mounted) setState(() => _refreshingAttribution = false);
  }

  Future<void> _exportCsv() async {
    final t = AppStrings.of(context);
    setState(() => _exporting = true);
    try {
      await _service.track('funnel_csv_exported');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/ai_wealth_tracker_funnel_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(_service.exportCsv(), encoding: utf8);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: t.text(AppStringKeys.funnelExportSubject));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final summary = _service.funnelSummary();
    final source = _service.sourceSummary();
    final events = _service.recentEvents().reversed.take(12).toList();

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.text(AppStringKeys.funnelSheetTitle),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    _FunnelAttributionCard(
                      source: source,
                      tokenReady: _service.attributionToken != null,
                      refreshing: _refreshingAttribution,
                      onRefresh: _refreshAttribution,
                    ),
                    const SizedBox(height: 12),
                    for (final step in summary)
                      _FunnelStepRow(step: step, t: t, colors: colors),
                    const SizedBox(height: 12),
                    Text(
                      t.text(AppStringKeys.funnelRecentEvents),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (events.isEmpty)
                      Text(
                        t.text(AppStringKeys.funnelNoEvents),
                        style: TextStyle(color: colors.textSecondary),
                      )
                    else
                      for (final event in events)
                        _FunnelEventRow(event: event, colors: colors),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : _exportCsv,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(t.text(AppStringKeys.funnelExportCsv)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FunnelAttributionCard extends StatelessWidget {
  const _FunnelAttributionCard({
    required this.source,
    required this.tokenReady,
    required this.refreshing,
    required this.onRefresh,
  });

  final Map<String, String> source;
  final bool tokenReady;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final rows = [
      (
        label: t.text(AppStringKeys.funnelStatus),
        value: source['apple_ads_attribution_status'] ?? '-',
      ),
      (
        label: t.text(AppStringKeys.funnelCountry),
        value:
            source['ad_country_or_region'] ?? source['locale_country'] ?? '-',
      ),
      (
        label: t.text(AppStringKeys.funnelCampaign),
        value: source['campaign_id'] ?? '-',
      ),
      (
        label: t.text(AppStringKeys.funnelAdGroup),
        value: source['ad_group_id'] ?? '-',
      ),
      (
        label: t.text(AppStringKeys.funnelKeyword),
        value: source['keyword_id'] ?? '-',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.textSecondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ads_click_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.text(AppStringKeys.funnelAttributionSection),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tokenReady
                ? t.text(AppStringKeys.funnelTokenReady)
                : t.text(AppStringKeys.funnelTokenMissing),
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            t.text(AppStringKeys.funnelAppleAdsNote),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(t.text(AppStringKeys.funnelRefreshAttribution)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelStepRow extends StatelessWidget {
  const _FunnelStepRow({
    required this.step,
    required this.t,
    required this.colors,
  });

  final FunnelStepSummary step;
  final AppStrings t;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final rate = step.conversionFromPrevious == null
        ? null
        : '${(step.conversionFromPrevious! * 100).clamp(0, 999).toStringAsFixed(0)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${step.count}',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (rate != null)
                  Text(
                    t.text(
                      AppStringKeys.funnelConversion,
                      params: {'rate': rate},
                    ),
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 112,
            child: Text(
              step.eventName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelEventRow extends StatelessWidget {
  const _FunnelEventRow({required this.event, required this.colors});

  final Map<String, Object?> event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.tryParse('${event['timestamp'] ?? ''}');
    final timeText = timestamp == null
        ? ''
        : DateFormat('MM-dd HH:mm').format(timestamp);
    final properties = event['properties'] is Map
        ? Map<String, Object?>.from(event['properties']! as Map)
        : <String, Object?>{};
    final sourceText = [
      properties['locale_country'],
      properties['keyword_id'] == null
          ? null
          : 'kw ${properties['keyword_id']}',
      properties['campaign_id'] == null
          ? null
          : 'camp ${properties['campaign_id']}',
    ].whereType<Object>().join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardBackground.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.textSecondary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (sourceText.isNotEmpty)
                  Text(
                    sourceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            timeText,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeSheet extends StatelessWidget {
  const _ThemeModeSheet({required this.currentPreference});

  final AppThemePreference currentPreference;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final options = [
      (preference: AppThemePreference.light, icon: Icons.light_mode_outlined),
      (preference: AppThemePreference.dark, icon: Icons.dark_mode_outlined),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.text(AppStringKeys.settingsThemeModeSheetTitle),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            for (final option in options)
              PressFeedback(
                onTap: () => Navigator.pop(context, option.preference),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: option.preference == currentPreference
                          ? AppColors.primary.withValues(alpha: 0.42)
                          : colors.textSecondary.withValues(alpha: 0.12),
                    ),
                    boxShadow: colors.softShadow,
                  ),
                  child: Row(
                    children: [
                      Icon(option.icon, color: colors.textPrimary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _settingsThemeModeLabel(context, option.preference),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        option.preference == currentPreference
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: option.preference == currentPreference
                            ? AppColors.primary
                            : colors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 分组头部
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 分割线（仅在列表项之间）
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Divider(
      height: 1,
      thickness: 1,
      color: colors.textSecondary.withValues(alpha: 0.12),
      indent: 16,
      endIndent: 16,
    );
  }
}

/// 设置列表项（统一高度48px）
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return PressFeedback(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(minHeight: hasSubtitle ? 64 : 48),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: hasSubtitle ? 10 : 0,
        ),
        child: Row(
          crossAxisAlignment: hasSubtitle
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: hasSubtitle ? 4 : 0),
              child: Icon(icon, size: 24, color: colors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: titleColor ?? colors.textPrimary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: EdgeInsets.only(top: hasSubtitle ? 6 : 0),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      constraints: BoxConstraints(minHeight: hasSubtitle ? 64 : 48),
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: hasSubtitle ? 8 : 0,
        bottom: hasSubtitle ? 8 : 0,
      ),
      child: Row(
        crossAxisAlignment: hasSubtitle
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: hasSubtitle ? 8 : 0),
            child: Icon(icon, size: 24, color: colors.textPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// 导出日期范围选择底部弹窗
class _ExportDateRangeSheet extends StatefulWidget {
  final DateTimeRange? initialRange;
  const _ExportDateRangeSheet({this.initialRange});

  @override
  State<_ExportDateRangeSheet> createState() => _ExportDateRangeSheetState();
}

class _ExportDateRangeSheetState extends State<_ExportDateRangeSheet> {
  late DateTimeRange _selectedRange;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange ?? _thisMonthRange();
  }

  DateTimeRange _thisMonthRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  DateTimeRange _lastMonthRange() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    return DateTimeRange(
      start: lastMonth,
      end: DateTime(now.year, now.month, 0),
    );
  }

  DateTimeRange _last3MonthsRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month - 3, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.text(AppStringKeys.settingsExportSheetTitle),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // 快捷选项
            _RangeOption(
              label: t.text(AppStringKeys.settingsExportRangeThisMonth),
              range: _thisMonthRange(),
              dateFormat: _settingsShortDate,
              selected: _selectedRange == _thisMonthRange(),
              onTap: () => setState(() => _selectedRange = _thisMonthRange()),
            ),
            _RangeOption(
              label: t.text(AppStringKeys.settingsExportRangeLastMonth),
              range: _lastMonthRange(),
              dateFormat: _settingsShortDate,
              selected: _selectedRange == _lastMonthRange(),
              onTap: () => setState(() => _selectedRange = _lastMonthRange()),
            ),
            _RangeOption(
              label: t.text(AppStringKeys.settingsExportRangeLast3Months),
              range: _last3MonthsRange(),
              dateFormat: _settingsShortDate,
              selected: _selectedRange == _last3MonthsRange(),
              onTap: () => setState(() => _selectedRange = _last3MonthsRange()),
            ),
            _RangeOption(
              label: t.text(AppStringKeys.settingsExportRangeCustom),
              range: null,
              dateFormat: _settingsShortDate,
              selected: false,
              customSelected: _customStart != null,
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _customStart != null
                      ? DateTimeRange(
                          start: _customStart!,
                          end: _customEnd ?? DateTime.now(),
                        )
                      : null,
                );
                if (picked != null) {
                  setState(() {
                    _customStart = picked.start;
                    _customEnd = picked.end;
                    _selectedRange = picked;
                  });
                }
              },
            ),

            if (_customStart != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Text(
                  t.text(
                    AppStringKeys.settingsExportRangeSelected,
                    params: {
                      'start': _settingsShortDate(_customStart!),
                      'end': _settingsShortDate(_customEnd!),
                    },
                  ),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A47D8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context, _selectedRange),
                child: Text(t.text(AppStringKeys.settingsExportConfirm)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeOption extends StatelessWidget {
  final String label;
  final DateTimeRange? range;
  final String Function(DateTime) dateFormat;
  final bool selected;
  final bool customSelected;
  final VoidCallback onTap;

  const _RangeOption({
    required this.label,
    required this.range,
    required this.dateFormat,
    required this.selected,
    this.customSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isActive = range != null ? selected : customSelected;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        range != null ? Icons.calendar_today : Icons.date_range,
        color: isActive ? AppColors.primary : colors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppColors.primary : colors.textPrimary,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: range != null
          ? Text(
              '${dateFormat(range!.start)} ~ ${dateFormat(range!.end)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: isActive
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

// 分类管理底部弹窗
// 自定义类目管理 Bottom Sheet
class _CategoryManagerSheet extends StatelessWidget {
  final ScrollController scrollController;
  const _CategoryManagerSheet({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<CustomCategoryBloc>()..add(const LoadCustomCategories()),
      child: _CategoryManagerBody(scrollController: scrollController),
    );
  }
}

class _CategoryManagerBody extends StatelessWidget {
  final ScrollController scrollController;
  const _CategoryManagerBody({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CustomCategoryBloc, CustomCategoryState>(
      builder: (context, state) {
        final t = AppStrings.of(context);
        final colors = Theme.of(context).extension<AppColorsExtension>()!;
        final customExpense = state.expenseCategories;
        final customIncome = state.incomeCategories;

        return Container(
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 拖动条
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题栏
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.text(AppStringKeys.categoryManagerTitle),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, color: Color(0xFF4A47D8)),
                          onPressed: () {
                            _showAddCategorySheet(
                              context,
                              CustomCategoryType.expense,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.textSecondary.withValues(alpha: 0.12),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.of(context).padding.bottom + 120,
                  ),
                  children: [
                    // 支出类目
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        t.text(AppStringKeys.categorySystemExpenseTitle),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    _CategoryGrid(
                      categories: CategoryDef.expenseCategories
                          .map(
                            (c) => _CategoryItem(
                              id: c.id,
                              name: localizedCategoryName(
                                id: c.id,
                                fallback: c.name,
                                locale: _settingsLocale(),
                              ),
                              icon: c.icon,
                              isSystem: true,
                            ),
                          )
                          .toList(),
                      onDelete: null,
                      onEdit: null,
                    ),

                    if (customExpense.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t.text(AppStringKeys.categoryCustomExpenseTitle),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      _CategoryGrid(
                        categories: customExpense
                            .map(
                              (c) => _CategoryItem(
                                name: c.name,
                                icon: c.icon,
                                isSystem: false,
                                id: c.id,
                              ),
                            )
                            .toList(),
                        onDelete: (id) {
                          context.read<CustomCategoryBloc>().add(
                            DeleteCustomCategoryEvent(id),
                          );
                        },
                        onEdit: (item) {
                          _showEditCategorySheet(
                            context,
                            customExpense.firstWhere((c) => c.id == item.id),
                          );
                        },
                      ),
                    ],

                    // 收入类目
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        t.text(AppStringKeys.categorySystemIncomeTitle),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    _CategoryGrid(
                      categories: CategoryDef.incomeCategories
                          .map(
                            (c) => _CategoryItem(
                              id: c.id,
                              name: localizedCategoryName(
                                id: c.id,
                                fallback: c.name,
                                locale: _settingsLocale(),
                              ),
                              icon: c.icon,
                              isSystem: true,
                            ),
                          )
                          .toList(),
                      onDelete: null,
                      onEdit: null,
                    ),

                    if (customIncome.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t.text(AppStringKeys.categoryCustomIncomeTitle),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      _CategoryGrid(
                        categories: customIncome
                            .map(
                              (c) => _CategoryItem(
                                name: c.name,
                                icon: c.icon,
                                isSystem: false,
                                id: c.id,
                              ),
                            )
                            .toList(),
                        onDelete: (id) {
                          context.read<CustomCategoryBloc>().add(
                            DeleteCustomCategoryEvent(id),
                          );
                        },
                        onEdit: (item) {
                          _showEditCategorySheet(
                            context,
                            customIncome.firstWhere((c) => c.id == item.id),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddCategorySheet(BuildContext context, CustomCategoryType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CategoryFormSheet(
        type: type,
        onSave: (name, icon, type) async {
          if (type == CustomCategoryType.expense) {
            getIt<QuickChipService>().addId(name);
          }
          final bloc = context.read<CustomCategoryBloc>();
          // 监听 bloc，等状态变为 loaded（即 categories 已更新）后再关闭 sheet
          late final StreamSubscription sub;
          sub = bloc.stream.listen((state) {
            if (state.status == CustomCategoryStatus.loaded) {
              sub.cancel();
              if (ctx.mounted) Navigator.pop(ctx);
            }
          });
          bloc.add(AddCustomCategoryEvent(name: name, icon: icon, type: type));
        },
      ),
    );
  }

  void _showEditCategorySheet(BuildContext context, CustomCategory category) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CategoryFormSheet(
        category: category,
        type: category.type,
        onSave: (name, icon, type) async {
          context.read<CustomCategoryBloc>().add(
            UpdateCustomCategoryEvent(
              category.copyWith(name: name, icon: icon),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryItem {
  final String id;
  final String name;
  final String icon;
  final bool isSystem;
  _CategoryItem({
    required this.name,
    required this.icon,
    this.isSystem = true,
    this.id = '',
  });
}

class _CategoryGrid extends StatelessWidget {
  final List<_CategoryItem> categories;
  final void Function(String id)? onDelete;
  final void Function(_CategoryItem)? onEdit;

  const _CategoryGrid({
    required this.categories,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((c) {
        final isActive = !c.isSystem && onDelete != null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.14)
                : colors.background,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: AppColors.primary, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.isSystem
                      ? AppColors.getCategoryColor(c.id).withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (c.isSystem
                                  ? AppColors.getCategoryColor(c.id)
                                  : const Color(0xFF7A35FF))
                              .withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(c.icon, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Text(c.name, style: TextStyle(color: colors.textPrimary)),
              if (!c.isSystem) ...[
                const SizedBox(width: 4),
                PressFeedback(
                  onTap: () => onEdit?.call(c),
                  child: Icon(
                    Icons.edit,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                PressFeedback(
                  onTap: () => _confirmDelete(context, c, onDelete!),
                  child: const Icon(Icons.close, size: 14, color: Colors.red),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  void _confirmDelete(
    BuildContext context,
    _CategoryItem item,
    void Function(String) onDelete,
  ) {
    final t = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
          title: Text(t.text(AppStringKeys.categoryDeleteTitle)),
          content: Text(
            t.text(
              AppStringKeys.categoryDeleteContent,
              params: {'name': item.name},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.text(AppStringKeys.commonCancel)),
            ),
            TextButton(
              onPressed: () {
                onDelete(item.id);
                Navigator.pop(ctx);
              },
              child: Text(
                t.text(AppStringKeys.commonDelete),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryFormSheet extends StatefulWidget {
  final CustomCategory? category;
  final CustomCategoryType type;
  final Future<void> Function(String name, String icon, CustomCategoryType type)
  onSave;

  const _CategoryFormSheet({
    this.category,
    required this.type,
    required this.onSave,
  });

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late final TextEditingController _nameController;
  late String _selectedIcon;
  Completer<void>? _saveCompleter;

  // App 风格 emoji 图标选择
  static const List<String> _iconOptions = [
    '🍜',
    '🚗',
    '🛒',
    '🎮',
    '🏠',
    '💊',
    '📚',
    '💅',
    '👥',
    '✈️',
    '⚽',
    '☕',
    '🍬',
    '🍎',
    '🧴',
    '📦',
    '🍱',
    '🥬',
    '🧃',
    '👔',
    '📱',
    '🏘️',
    '🏦',
    '🏡',
    '🎁',
    '🚬',
    '🌟',
    '🎲',
    '📲',
    '🎬',
    '🚙',
    '🏍️',
    '⛽',
    '📖',
    '📓',
    '🐶',
    '💧',
    '⚡',
    '🔥',
    '👶',
    '👴',
    '🔑',
    '💼',
    '🔧',
    '🎟️',
    '💝',
    '🀄',
    '💰',
    '🎁',
    '📈',
    '🧧',
    '↩️',
    '💵',
    '🤝',
    '💳',
    '↙️',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.category?.icon ?? _iconOptions.first;
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onIconSelected(String icon) {
    setState(() {
      _selectedIcon = icon;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            120,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.category == null
                      ? t.text(AppStringKeys.categoryCreateTitle)
                      : t.text(AppStringKeys.categoryEditTitle),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: t.text(AppStringKeys.categoryNameLabel),
                    hintText: t.text(AppStringKeys.categoryNameHint),
                    filled: true,
                    fillColor: colors.background,
                    labelStyle: TextStyle(color: colors.textSecondary),
                    hintStyle: TextStyle(color: colors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colors.textSecondary.withValues(alpha: 0.18),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colors.textSecondary.withValues(alpha: 0.18),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t.text(AppStringKeys.categorySelectIcon),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: GridView.count(
                    crossAxisCount: 8,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    children: _iconOptions.map((icon) {
                      final selected = icon == _selectedIcon;
                      return PressFeedback(
                        onTap: () => _onIconSelected(icon),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.14)
                                : colors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: selected
                                ? Border.all(color: AppColors.primary, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      t.text(AppStringKeys.categoryPreview),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF7A35FF,
                                  ).withValues(alpha: 0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              _selectedIcon,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _nameController.text.isEmpty
                                ? t.text(AppStringKeys.categoryNamePlaceholder)
                                : _nameController.text,
                            style: TextStyle(color: colors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A47D8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed:
                        (_saveCompleter != null && !_saveCompleter!.isCompleted)
                        ? null
                        : () => _save(),
                    child:
                        (_saveCompleter != null && !_saveCompleter!.isCompleted)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(t.text(AppStringKeys.commonSave)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saveCompleter != null && !_saveCompleter!.isCompleted) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text(AppStringKeys.categoryNameRequired),
          ),
        ),
      );
      return;
    }
    final completer = Completer<void>();
    _saveCompleter = completer;
    setState(() {}); // 触发按钮立即禁用
    try {
      await widget.onSave(name, _selectedIcon, widget.type);
      if (!completer.isCompleted) completer.complete();
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    } finally {
      _saveCompleter = null;
      setState(() {});
    }
  }
}

// 会员 Banner（页面最顶部）
class _VipBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vipService = getIt<VipService>();
    final t = AppStrings.of(context);
    return ListenableBuilder(
      listenable: vipService,
      builder: (context, _) {
        final isVip = vipService.isVip;
        final expireDate = vipService.expireDate;

        return PremiumVipCard(
          badgeLabel: t.text(AppStringKeys.vipBadgeLabel),
          statusLabel: isVip ? t.text(AppStringKeys.vipStatusActive) : null,
          title: isVip
              ? t.text(AppStringKeys.vipActiveTitle)
              : t.text(AppStringKeys.vipOpenTitle),
          subtitle: isVip
              ? t.text(
                  AppStringKeys.vipExpireAt,
                  params: {
                    'date': expireDate != null
                        ? _settingsShortDateTime(expireDate)
                        : '—',
                  },
                )
              : t.text(AppStringKeys.vipUnlockFeatures),
          actionLabel: isVip
              ? t.text(AppStringKeys.vipManage)
              : t.text(AppStringKeys.vipOpen),
          onTap: () => _showVipPurchaseSheet(context),
        );
      },
    );
  }

  void _showVipPurchaseSheet(BuildContext context) {
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'paywall_opened',
        properties: {'source': 'settings_vip_banner'},
      ),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.52,
        maxChildSize: 0.9,
        builder: (context, scrollController) =>
            _VipPurchaseSheet(scrollController: scrollController),
      ),
    );
  }
}

// 会员购买底部弹窗
class _VipPurchaseSheet extends StatefulWidget {
  final ScrollController? scrollController;

  const _VipPurchaseSheet({this.scrollController});

  @override
  State<_VipPurchaseSheet> createState() => _VipPurchaseSheetState();
}

class _VipPurchaseSheetState extends State<_VipPurchaseSheet> {
  VipType _selectedType = resolveVipStoreProvider() == VipStoreProvider.huawei
      ? VipType.lifetime
      : VipType.monthly;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _hasProductLoadError = false;
  ProductDetails? _monthlyProduct;
  ProductDetails? _yearlyProduct;
  ProductDetails? _lifetimeProduct;

  @override
  void initState() {
    super.initState();
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'paywall_viewed',
        properties: {'surface': 'vip_sheet'},
      ),
    );
    _loadProducts();
  }

  void _selectPlan(VipType type) {
    setState(() => _selectedType = type);
    unawaited(
      getIt<FunnelAnalyticsService>().track(
        'subscription_plan_selected',
        properties: {'plan': type.name},
      ),
    );
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _isLoadingProducts = true;
        _hasProductLoadError = false;
      });
    }
    try {
      final vipService = getIt<VipService>();
      final isHuaweiStore =
          resolveVipStoreProvider() == VipStoreProvider.huawei;
      final monthlyId = resolveVipProductId(type: VipType.monthly);
      final yearlyId = resolveVipProductId(type: VipType.yearly);
      final lifetimeId = resolveVipProductId(type: VipType.lifetime);
      final result = await vipService.queryVipProductDetails();

      debugPrint(
        '[VipSheet] queryProductDetails found=${result.productDetails.length}, notFound=${result.notFoundIDs.join(',')}',
      );
      if (result.error != null) {
        debugPrint(
          '[VipSheet] queryProductDetails error=${result.error!.code}, message=${result.error!.message}, details=${result.error!.details}',
        );
      }
      for (final product in result.productDetails) {
        debugPrint(
          '[VipSheet] product id=${product.id}, price=${product.price}, currencyCode=${product.currencyCode}, rawPrice=${product.rawPrice}',
        );
      }

      ProductDetails? monthly;
      ProductDetails? yearly;
      ProductDetails? lifetime;
      for (final product in result.productDetails) {
        if (product.id == monthlyId) monthly = product;
        if (product.id == yearlyId) yearly = product;
        if (product.id == lifetimeId) lifetime = product;
      }

      if (!mounted) return;
      setState(() {
        _monthlyProduct = monthly;
        _yearlyProduct = yearly;
        _lifetimeProduct = lifetime;
        _hasProductLoadError = isHuaweiStore
            ? lifetime == null
            : monthly == null && yearly == null;
        _isLoadingProducts = false;
      });
    } catch (error, stackTrace) {
      debugPrint('[VipSheet] queryProductDetails failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _hasProductLoadError = true;
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _confirmVipChangeInBackground(
    VipService vipService,
    VipType previousType,
    DateTime? previousExpire,
    AppStrings t,
  ) async {
    final previousMs = previousExpire?.millisecondsSinceEpoch;
    var changed = false;
    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final refreshed = await vipService.refreshFromAppStoreServer();
      if (!refreshed) {
        await vipService.syncFromCloud();
      }
      final currentMs = vipService.expireDate?.millisecondsSinceEpoch;
      if ((currentMs != null && currentMs != previousMs) ||
          vipService.vipType != previousType) {
        changed = true;
        break;
      }
    }
    if (!mounted) return;
    final currentExpire = vipService.expireDate;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed && currentExpire != null
              ? t.text(
                  AppStringKeys.vipUpdated,
                  params: {'date': _settingsShortDateTime(currentExpire)},
                )
              : t.text(AppStringKeys.vipUnchanged),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vipService = getIt<VipService>();
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final bottomScrollTail = MediaQuery.of(context).padding.bottom + 84.0;

    return SafeArea(
      top: false,
      child: Material(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: vipService,
          builder: (context, _) {
            final isVip = vipService.isVip;
            final isHuaweiStore =
                resolveVipStoreProvider() == VipStoreProvider.huawei;
            final hasMonthlyProduct = _monthlyProduct != null;
            final hasYearlyProduct = _yearlyProduct != null;
            final hasLifetimeProduct = _lifetimeProduct != null;
            final selectedProductLoaded = switch (_selectedType) {
              VipType.monthly => hasMonthlyProduct,
              VipType.yearly => hasYearlyProduct,
              VipType.lifetime => hasLifetimeProduct,
              VipType.none => false,
            };
            final showProductLoadError =
                _hasProductLoadError && !selectedProductLoaded;
            final monthlyPrice =
                _monthlyProduct?.price ?? t.text(AppStringKeys.vipLoadingPrice);
            final yearlyPrice =
                _yearlyProduct?.price ?? t.text(AppStringKeys.vipLoadingPrice);
            final lifetimePrice =
                _lifetimeProduct?.price ??
                (isHuaweiStore ? '¥28' : t.text(AppStringKeys.vipLoadingPrice));
            final yearlyCurrency = _yearlyProduct?.currencyCode;
            final yearlyRawPrice = _yearlyProduct?.rawPrice;
            final yearlyMonthlyPrice =
                yearlyRawPrice == null || yearlyCurrency == null
                ? t.text(AppStringKeys.vipLoadingPrice)
                : _settingsMoney(
                    yearlyRawPrice / 12,
                    currencyCode: yearlyCurrency,
                    decimalDigits: 2,
                  );

            return SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textSecondary.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.text(AppStringKeys.vipOpenTitle),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _VipBenefitList(t: t, colors: colors),
                  const SizedBox(height: 16),
                  if (isVip) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A47D8).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF4A47D8),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t.text(
                              AppStringKeys.vipExpireUntil,
                              params: {
                                'date': vipService.expireDate != null
                                    ? _settingsShortDateTime(
                                        vipService.expireDate!,
                                      )
                                    : '—',
                              },
                            ),
                            style: const TextStyle(
                              color: Color(0xFF4A47D8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    isHuaweiStore
                        ? t.text(AppStringKeys.vipSelectLifetime)
                        : t.text(AppStringKeys.vipSelectPlan),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isHuaweiStore) ...[
                    _VipOptionTile(
                      title: t.text(AppStringKeys.vipLifetimeTitle),
                      price: lifetimePrice,
                      period: t.text(AppStringKeys.vipLifetimePeriod),
                      icon: '✓',
                      isSelected: _selectedType == VipType.lifetime,
                      onTap: () => _selectPlan(VipType.lifetime),
                      badge: t.text(AppStringKeys.vipRecommended),
                    ),
                  ] else ...[
                    _VipOptionTile(
                      title: t.text(AppStringKeys.vipMonthlyTitle),
                      price: monthlyPrice,
                      period: t.text(AppStringKeys.vipMonthlyPeriod),
                      icon: '📅',
                      isSelected: _selectedType == VipType.monthly,
                      onTap: () => _selectPlan(VipType.monthly),
                    ),
                    const SizedBox(height: 8),
                    _VipOptionTile(
                      title: t.text(AppStringKeys.vipYearlyTitle),
                      price: yearlyPrice,
                      period: t.text(
                        AppStringKeys.vipYearlyPeriod,
                        params: {'price': yearlyMonthlyPrice},
                      ),
                      icon: '🎁',
                      isSelected: _selectedType == VipType.yearly,
                      onTap: () => _selectPlan(VipType.yearly),
                      badge: t.text(AppStringKeys.vipRecommended),
                    ),
                  ],
                  if (showProductLoadError) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Color(0xFFB26A00),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.text(AppStringKeys.vipPaymentUnavailable),
                              style: const TextStyle(
                                color: Color(0xFF7A4B00),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoadingProducts
                                ? null
                                : _loadProducts,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF5C6BC0),
                              minimumSize: const Size(48, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(t.text(AppStringKeys.commonRetry)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      t.text(AppStringKeys.vipConsent),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isLoading || !selectedProductLoaded
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                unawaited(
                                  getIt<FunnelAnalyticsService>().track(
                                    'subscription_cta_tapped',
                                    properties: {'plan': _selectedType.name},
                                  ),
                                );
                                final previousType = vipService.vipType;
                                final previousExpire = vipService.expireDate;
                                final started = switch (_selectedType) {
                                  VipType.monthly =>
                                    await vipService.purchaseMonthly(),
                                  VipType.yearly =>
                                    await vipService.purchaseYearly(),
                                  VipType.lifetime =>
                                    await vipService.purchaseLifetimeAdFree(),
                                  VipType.none => false,
                                };
                                unawaited(
                                  getIt<FunnelAnalyticsService>().track(
                                    started
                                        ? 'subscription_checkout_started'
                                        : 'subscription_checkout_unavailable',
                                    properties: {'plan': _selectedType.name},
                                  ),
                                );
                                if (!started && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        t.text(
                                          AppStringKeys.vipProductUnavailable,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                if (started) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          t.text(AppStringKeys.vipConfirming),
                                        ),
                                      ),
                                    );
                                  }
                                  unawaited(
                                    _confirmVipChangeInBackground(
                                      vipService,
                                      previousType,
                                      previousExpire,
                                      t,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        t.text(
                                          AppStringKeys.vipOpenFailed,
                                          params: {'error': '$e'},
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              !selectedProductLoaded
                                  ? showProductLoadError
                                        ? t.text(
                                            AppStringKeys
                                                .vipPaymentUnavailableCta,
                                          )
                                        : t.text(AppStringKeys.vipLoadingPrice)
                                  : isVip
                                  ? t.text(
                                      AppStringKeys.vipRenewConfirm,
                                      params: {
                                        'period': switch (_selectedType) {
                                          VipType.monthly => t.text(
                                            AppStringKeys.vipPeriodMonthly,
                                          ),
                                          VipType.yearly => t.text(
                                            AppStringKeys.vipPeriodYearly,
                                          ),
                                          VipType.lifetime => t.text(
                                            AppStringKeys.vipPeriodLifetime,
                                          ),
                                          VipType.none => '',
                                        },
                                      },
                                    )
                                  : t.text(
                                      AppStringKeys.vipSubscribeNow,
                                      params: {
                                        'price': switch (_selectedType) {
                                          VipType.monthly => t.text(
                                            AppStringKeys.vipPriceMonthly,
                                            params: {'price': monthlyPrice},
                                          ),
                                          VipType.yearly => t.text(
                                            AppStringKeys.vipPriceYearly,
                                            params: {'price': yearlyPrice},
                                          ),
                                          VipType.lifetime => t.text(
                                            AppStringKeys.vipPriceLifetime,
                                            params: {'price': lifetimePrice},
                                          ),
                                          VipType.none => '',
                                        },
                                      },
                                    ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      t.text(
                        Theme.of(context).platform == TargetPlatform.android
                            ? AppStringKeys.vipPaymentHintAndroid
                            : AppStringKeys.vipPaymentHint,
                      ),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: PressFeedback(
                      onTap: () async {
                        final url = Uri.parse(
                          getIt<AppProfileService>().termsOfServiceUrl,
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.inAppBrowserView,
                          );
                        }
                      },
                      child: Text(
                        t.text(AppStringKeys.vipConsent),
                        style: const TextStyle(
                          color: Color(0xFF5C6BC0),
                          fontSize: 11,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await vipService.restorePurchases();
                      },
                      child: Text(
                        t.text(AppStringKeys.vipRestorePurchase),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  SizedBox(height: bottomScrollTail),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VipBenefitList extends StatelessWidget {
  const _VipBenefitList({required this.t, required this.colors});

  final AppStrings t;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final benefits = [
      t.text(AppStringKeys.vipBenefitAiReport),
      t.text(AppStringKeys.vipBenefitBudgetWarning),
      t.text(AppStringKeys.vipBenefitUnlimited),
      t.text(AppStringKeys.vipBenefitAssets),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4A47D8).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4A47D8).withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          for (final benefit in benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF4A47D8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      benefit,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VipOptionTile extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  const _VipOptionTile({
    required this.title,
    required this.price,
    required this.period,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return PressFeedback(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? const Color(0xFF5C6BC0)
                : colors.textSecondary.withValues(alpha: 0.24),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF5C6BC0).withValues(alpha: 0.05)
              : colors.background,
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    period,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF5C6BC0),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF5C6BC0),
                    size: 20,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 短信验证码输入对话框（账号注销用）
class _SmsCodeInputDialog extends StatefulWidget {
  final String phone;

  const _SmsCodeInputDialog({required this.phone});

  @override
  State<_SmsCodeInputDialog> createState() => _SmsCodeInputDialogState();
}

class _SmsCodeInputDialogState extends State<_SmsCodeInputDialog> {
  final _codeController = TextEditingController();
  bool _countingDown = false;
  int _countdown = 0;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _countdown = 60;
      _countingDown = true;
    });
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

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return AlertDialog(
      backgroundColor: colors.cardBackground,
      title: Text(t.text(AppStringKeys.smsCodeDialogTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.text(
              AppStringKeys.smsCodeDialogSentTo,
              params: {'phone': widget.phone},
            ),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: t.text(AppStringKeys.smsCodeDialogHint),
              hintStyle: TextStyle(color: colors.textSecondary),
              filled: true,
              fillColor: colors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colors.textSecondary.withValues(alpha: 0.24),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colors.textSecondary.withValues(alpha: 0.24),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF5C6BC0)),
              ),
              counterText: '',
              suffixIcon: _countingDown
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${_countdown}s',
                        style: const TextStyle(color: Color(0xFF5C6BC0)),
                      ),
                    )
                  : TextButton(
                      onPressed: () {
                        _startCountdown();
                      },
                      child: Text(
                        t.text(AppStringKeys.smsCodeDialogResend),
                        style: const TextStyle(color: Color(0xFF5C6BC0)),
                      ),
                    ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(t.text(AppStringKeys.commonCancel)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _codeController.text.trim()),
          child: Text(t.text(AppStringKeys.commonConfirm)),
        ),
      ],
    );
  }
}
