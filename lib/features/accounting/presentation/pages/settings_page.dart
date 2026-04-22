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
import '../../../../app/profile/capability_profile.dart';
import '../../../../core/formatters/app_formatter.dart';
import '../../../../core/formatters/category_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_string_keys.dart';
import '../../../../l10n/app_strings.dart';
import '../../../../services/injection.dart';
import '../../../../services/ai_privacy_consent_service.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/aliyun_sms_service.dart';
import '../../../../services/quick_chip_service.dart';
import '../../../../services/cloud_service.dart';
import '../../../../services/avatar_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/custom_category/custom_category.dart';
import '../bloc/custom_category/custom_category_bloc.dart';
import '../bloc/custom_category/custom_category_event.dart';
import '../bloc/custom_category/custom_category_state.dart';
import '../../../../services/vip_service.dart';
import '../../../../services/stock_service.dart';
import '../widgets/avatar_widgets.dart';
import '../widgets/press_feedback.dart';

Locale _settingsLocale() => getIt<AppProfileService>().currentLocale;

String _settingsShortDate(DateTime date) {
  return AppFormatter.formatShortDate(date, locale: _settingsLocale());
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
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4A47D8), Color(0xFF6D5DF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          t.text(AppStringKeys.settingsTitle),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: LayoutBuilder(
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
                  // 会员专属卡片（页面最顶部）
                  _VipBanner(),
                  const SizedBox(height: 16),

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
                    title: t.text(AppStringKeys.settingsCustomCategoriesTitle),
                    subtitle: t.text(
                      AppStringKeys.settingsCustomCategoriesSubtitle,
                    ),
                    onTap: () => _openCategoryManager(context),
                  ),
                  _SettingTile(
                    icon: Icons.smart_toy_outlined,
                    title: t.text(AppStringKeys.settingsAiConsentWithdrawTitle),
                    subtitle: t.text(
                      AppStringKeys.settingsAiConsentWithdrawSubtitle,
                    ),
                    onTap: () => _showWithdrawAIConsentDialog(context),
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

                  _SectionDivider(),
                  _SectionHeader(t.text(AppStringKeys.settingsAbout)),

                  _SettingTile(
                    icon: Icons.privacy_tip_outlined,
                    title: t.text(AppStringKeys.settingsPrivacyTitle),
                    onTap: () => _openPrivacyPolicy(context),
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
      builder: (ctx) => AlertDialog(
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
      ),
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
      builder: (ctx) => AlertDialog(
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
      ),
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
      builder: (ctx) => AlertDialog(
        title: Text(t.text(AppStringKeys.settingsDeleteAccountTitle)),
        content: Text(t.text(AppStringKeys.settingsDeleteDialogContent)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.text(AppStringKeys.commonCancel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.text(AppStringKeys.settingsDeleteConfirmAction)),
          ),
        ],
      ),
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
    // App Store 链接（临时用 App 名称搜索页）
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
      builder: (ctx) => AlertDialog(
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
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
    return Divider(
      height: 1,
      thickness: 1,
      color: const Color(0xFFF5F7FA),
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
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return PressFeedback(
      onTap: onTap,
      child: Container(
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
              child: Icon(icon, size: 24, color: const Color(0xFF303133)),
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
                      color: titleColor ?? const Color(0xFF303133),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF606266),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: EdgeInsets.only(top: hasSubtitle ? 6 : 0),
              child: const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF999999),
              ),
            ),
          ],
        ),
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.text(AppStringKeys.settingsExportSheetTitle),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(
                    color: Color(0xFF4A47D8),
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
    final isActive = range != null ? selected : customSelected;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        range != null ? Icons.calendar_today : Icons.date_range,
        color: isActive ? const Color(0xFF4A47D8) : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? const Color(0xFF4A47D8) : Colors.black,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: range != null
          ? Text(
              '${dateFormat(range!.start)} ~ ${dateFormat(range!.end)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            )
          : null,
      trailing: isActive
          ? const Icon(Icons.check_circle, color: Color(0xFF4A47D8))
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
        final customExpense = state.expenseCategories;
        final customIncome = state.incomeCategories;

        return Column(
          children: [
            // 拖动条
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            const Divider(height: 1),
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
                        color: Colors.grey,
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
                          color: Color(0xFF4A47D8),
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
                        color: Colors.grey,
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
                          color: Color(0xFF4A47D8),
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((c) {
        final isActive = !c.isSystem && onDelete != null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFF4F1FF) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: const Color(0xFF4A47D8), width: 1)
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
                      : const Color(0xFFF0EBFF),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: (c.isSystem
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
              Text(c.name),
              if (!c.isSystem) ...[
                const SizedBox(width: 4),
                PressFeedback(
                  onTap: () => onEdit?.call(c),
                  child: const Icon(Icons.edit, size: 14, color: Colors.grey),
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
      builder: (ctx) => AlertDialog(
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
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            120,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.category == null
                ? t.text(AppStringKeys.categoryCreateTitle)
                : t.text(AppStringKeys.categoryEditTitle),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // 类目名称
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: t.text(AppStringKeys.categoryNameLabel),
              hintText: t.text(AppStringKeys.categoryNameHint),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // 选择图标
          Text(
            t.text(AppStringKeys.categorySelectIcon),
            style: const TextStyle(fontWeight: FontWeight.w500),
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
                          ? const Color(0xFFF4F1FF)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: selected
                          ? Border.all(color: const Color(0xFF4A47D8), width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // 预览
          Row(
            children: [
              Text(
                t.text(AppStringKeys.categoryPreview),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1FF),
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
                        color: const Color(0xFFF0EBFF),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7A35FF).withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(_selectedIcon, style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _nameController.text.isEmpty
                          ? t.text(AppStringKeys.categoryNamePlaceholder)
                          : _nameController.text,
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
              child: (_saveCompleter != null && !_saveCompleter!.isCompleted)
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

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5C6BC0), Color(0xFF3F51B5)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('👑', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVip
                          ? t.text(AppStringKeys.vipActiveTitle)
                          : t.text(AppStringKeys.vipOpenTitle),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVip
                          ? t.text(
                              AppStringKeys.vipExpireAt,
                              params: {
                                'date': expireDate != null
                                    ? _settingsShortDate(expireDate)
                                    : '—',
                              },
                            )
                          : t.text(AppStringKeys.vipUnlockFeatures),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PressFeedback(
                onTap: () => _showVipPurchaseSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    isVip
                        ? t.text(AppStringKeys.vipManage)
                        : t.text(AppStringKeys.vipOpen),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVipPurchaseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _VipPurchaseSheet(),
    );
  }
}

// 会员购买底部弹窗
class _VipPurchaseSheet extends StatefulWidget {
  const _VipPurchaseSheet();

  @override
  State<_VipPurchaseSheet> createState() => _VipPurchaseSheetState();
}

class _VipPurchaseSheetState extends State<_VipPurchaseSheet> {
  VipType _selectedType = VipType.monthly;
  bool _isLoading = false;
  ProductDetails? _monthlyProduct;
  ProductDetails? _yearlyProduct;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final result = await InAppPurchase.instance.queryProductDetails({
        'com.phil.AIAccountant.mon',
        'com.phil.AIAccountant.year',
      });

      debugPrint(
        '[VipSheet] queryProductDetails found=${result.productDetails.length}, notFound=${result.notFoundIDs.join(',')}',
      );
      for (final product in result.productDetails) {
        debugPrint(
          '[VipSheet] product id=${product.id}, price=${product.price}, currencyCode=${product.currencyCode}, rawPrice=${product.rawPrice}',
        );
      }

      ProductDetails? monthly;
      ProductDetails? yearly;
      for (final product in result.productDetails) {
        if (product.id == 'com.phil.AIAccountant.mon') monthly = product;
        if (product.id == 'com.phil.AIAccountant.year') yearly = product;
      }

      if (!mounted) return;
      setState(() {
        _monthlyProduct = monthly;
        _yearlyProduct = yearly;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final vipService = getIt<VipService>();
    final isVip = vipService.isVip;
    final t = AppStrings.of(context);
    final hasMonthlyProduct = _monthlyProduct != null;
    final hasYearlyProduct = _yearlyProduct != null;
    final selectedProductLoaded = _selectedType == VipType.monthly
        ? hasMonthlyProduct
        : hasYearlyProduct;
    final monthlyPrice =
        _monthlyProduct?.price ?? t.text(AppStringKeys.vipLoadingPrice);
    final yearlyPrice =
        _yearlyProduct?.price ?? t.text(AppStringKeys.vipLoadingPrice);
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.text(AppStringKeys.vipOpenTitle),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
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
                              ? _settingsShortDate(vipService.expireDate!)
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
              t.text(AppStringKeys.vipSelectPlan),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // 月度会员
            _VipOptionTile(
              title: t.text(AppStringKeys.vipMonthlyTitle),
              price: monthlyPrice,
              period: t.text(AppStringKeys.vipMonthlyPeriod),
              icon: '📅',
              isSelected: _selectedType == VipType.monthly,
              onTap: () => setState(() => _selectedType = VipType.monthly),
            ),
            const SizedBox(height: 8),

            // 年度会员
            _VipOptionTile(
              title: t.text(AppStringKeys.vipYearlyTitle),
              price: yearlyPrice,
              period: t.text(
                AppStringKeys.vipYearlyPeriod,
                params: {'price': yearlyMonthlyPrice},
              ),
              icon: '🎁',
              isSelected: _selectedType == VipType.yearly,
              onTap: () => setState(() => _selectedType = VipType.yearly),
              badge: t.text(AppStringKeys.vipRecommended),
            ),
            const SizedBox(height: 20),

            // EULA consent — Apple 审核要求在购买流程中明确展示
            Center(
              child: Text(
                t.text(AppStringKeys.vipConsent),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
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
                          final started = _selectedType == VipType.monthly
                              ? await vipService.purchaseMonthly()
                              : await vipService.purchaseYearly();
                          if (!started && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  t.text(AppStringKeys.vipProductUnavailable),
                                ),
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
                            ? t.text(AppStringKeys.vipLoadingPrice)
                            : isVip
                            ? t.text(
                                AppStringKeys.vipRenewConfirm,
                                params: {
                                  'period': _selectedType == VipType.monthly
                                      ? t.text(AppStringKeys.vipPeriodMonthly)
                                      : t.text(AppStringKeys.vipPeriodYearly),
                                },
                              )
                            : t.text(
                                AppStringKeys.vipSubscribeNow,
                                params: {
                                  'price': _selectedType == VipType.monthly
                                      ? t.text(
                                          AppStringKeys.vipPriceMonthly,
                                          params: {'price': monthlyPrice},
                                        )
                                      : t.text(
                                          AppStringKeys.vipPriceYearly,
                                          params: {'price': yearlyPrice},
                                        ),
                                },
                              ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                t.text(AppStringKeys.vipPaymentHint),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
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
                    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
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
          ],
        ),
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
    return PressFeedback(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF5C6BC0) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF5C6BC0).withValues(alpha: 0.05)
              : null,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
    return AlertDialog(
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
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            autofocus: true,
            decoration: InputDecoration(
              hintText: t.text(AppStringKeys.smsCodeDialogHint),
              border: const OutlineInputBorder(),
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
