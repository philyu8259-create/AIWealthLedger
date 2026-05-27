import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'services/app_migration_service.dart';
import 'services/app_profile_service.dart';
import 'services/cloud_service.dart';
import 'services/config_service.dart';
import 'services/demo_data_seeder.dart';
import 'services/funnel_analytics_service.dart';
import 'services/injection.dart';
import 'services/vip_service.dart';

AppLifecycleListener? _vipLifecycleListener;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ——— 清除损坏数据（真机数据损坏保护）———
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('account_entries');
    if (raw != null) {
      try {
        jsonDecode(raw);
      } catch (_) {
        await prefs.remove('account_entries');
        debugPrint('[main] Corrupted account_entries cleared');
      }
    }
  } catch (e) {
    debugPrint('[main] prefs check error: $e');
  }

  // ——— 全局错误捕获 ———
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('=== FLUTTER ERROR ===');
    debugPrint(details.exceptionAsString());
    debugPrint('Library: ${details.library}');
    debugPrint('Context: ${details.context}');
    debugPrint('Stack: ${details.stack}');
    FlutterError.presentError(details);
  };

  await initializeDateFormatting('zh_CN', null);
  await initializeDateFormatting('en_US', null);
  await initializeDateFormatting('en_GB', null);
  await initializeDateFormatting('en_AU', null);

  try {
    await ConfigService.instance.load();
    debugPrint('[main] Config loaded');
  } catch (e) {
    debugPrint('[main] Config load error: $e');
  }

  try {
    await configureDependencies();
    debugPrint('[main] Dependencies configured');
    final funnelAnalytics = getIt<FunnelAnalyticsService>();
    unawaited(_refreshAppleAdsAttribution(funnelAnalytics));
    await funnelAnalytics.trackAppOpen();

    if (_subscriptionsEnabled) {
      _vipLifecycleListener ??= AppLifecycleListener(
        onResume: () {
          unawaited(_syncVipOnResume());
        },
      );
    }
  } catch (e, st) {
    debugPrint('[main] Dependency config error: $e\n$st');
  }

  try {
    await getIt<AppMigrationService>().run(
      deviceLocale: WidgetsBinding.instance.platformDispatcher.locale,
    );
    debugPrint('[main] AppMigrationService done');
  } catch (e, st) {
    debugPrint('[main] AppMigrationService error: $e\n$st');
  }

  // Demo 模式下，提前 seed 数据到 SharedPreferences
  // 这样 Bloc 首次 getEntries 时就能读到
  try {
    await DemoDataSeeder.seedIfNeeded();
    debugPrint('[main] DemoDataSeeder done');
  } catch (e) {
    debugPrint('[main] DemoDataSeeder error: $e');
  }

  runApp(const AIAccountingApp());

  // 会员恢复与云端同步改为首帧后后台进行，避免冷启动卡在 app logo 页面。
  if (_subscriptionsEnabled) {
    unawaited(_bootstrapVipAfterLaunch());
  }
}

bool get _subscriptionsEnabled {
  try {
    return getIt<AppProfileService>()
        .currentProfile
        .capabilityProfile
        .isEnabled('subscriptions');
  } catch (_) {
    return false;
  }
}

Future<void> _refreshAppleAdsAttribution(
  FunnelAnalyticsService funnelAnalytics,
) async {
  await funnelAnalytics.refreshAttributionContext();
  final token = funnelAnalytics.attributionToken;
  if (token == null || token.isEmpty) return;

  final payload = await getIt<CloudService>().fetchAppleAdsAttribution(token);
  if (payload == null || payload.isEmpty) return;
  await funnelAnalytics.saveAttributionPayload(payload);
}

Future<void> _bootstrapVipAfterLaunch() async {
  try {
    final vipService = getIt<VipService>();
    await vipService.init();
    debugPrint('[main] VipService init done');
    // 不在启动时自动刷新 App Store receipt。
    // 模拟器/无本地收据设备会因此弹 Apple 账号登录框，并可能在登录后继续循环弹出。
    // 会员状态优先由云端档案恢复；本地收据只在购买完成或用户手动“恢复购买”时读取。
    await vipService.syncFromCloud();
    debugPrint('[main] VipService syncFromCloud done');
  } catch (e) {
    debugPrint('[main] VipService init/restore error: $e');
  }
}

Future<void> _syncVipOnResume() async {
  try {
    final vipService = getIt<VipService>();
    await vipService.syncFromCloud();
    debugPrint('[main] VipService syncFromCloud on resume done');
  } catch (e) {
    debugPrint('[main] VipService syncFromCloud on resume error: $e');
  }
}
