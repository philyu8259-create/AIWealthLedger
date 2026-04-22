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

    _vipLifecycleListener ??= AppLifecycleListener(
      onResume: () {
        unawaited(_syncVipOnResume());
      },
    );
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
    // 冷启动不再自动调 restorePurchases。
    // 原因：真机上曾出现 iOS 原生层 EXC_BAD_ACCESS，崩溃点紧贴 restorePurchases 调用。
    // 会员状态优先由云端档案恢复，手动“恢复购买”入口仍保留给用户主动触发。
    await getIt<VipService>().syncFromCloud();
    debugPrint('[main] VipService syncFromCloud done');
  } catch (e) {
    debugPrint('[main] VipService init/restore error: $e');
  }
}

Future<void> _syncVipOnResume() async {
  try {
    await getIt<VipService>().syncFromCloud();
    debugPrint('[main] VipService syncFromCloud on resume done');
  } catch (e) {
    debugPrint('[main] VipService syncFromCloud on resume error: $e');
  }
}
