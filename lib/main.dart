import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'services/app_migration_service.dart';
import 'services/config_service.dart';
import 'services/demo_data_seeder.dart';
import 'services/injection.dart';
import 'services/vip_service.dart';

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
  unawaited(_bootstrapVipAfterLaunch());
}

Future<void> _bootstrapVipAfterLaunch() async {
  try {
    await getIt<VipService>().init();
    debugPrint('[main] VipService init done');
    // 自动恢复历史购买（确保重新安装 app 后会员状态恢复）
    await getIt<VipService>().restorePurchases();
    debugPrint('[main] VipService restorePurchases done');
    // 启动后尝试从云端同步 VIP 档案（云端为权威）
    await getIt<VipService>().syncFromCloud();
    debugPrint('[main] VipService syncFromCloud done');
  } catch (e) {
    debugPrint('[main] VipService init/restore error: $e');
  }
}
