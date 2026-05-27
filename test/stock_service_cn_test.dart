import 'dart:io';

import 'package:ai_accounting_app/app/app_flavor.dart';
import 'package:ai_accounting_app/services/app_profile_service.dart';
import 'package:ai_accounting_app/services/cloud_service.dart';
import 'package:ai_accounting_app/services/config_service.dart';
import 'package:ai_accounting_app/services/stock_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StockService> _loadCnStockService() async {
  await GetIt.instance.reset();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  GetIt.instance.registerSingleton<SharedPreferences>(prefs);

  final envDir = await Directory.systemTemp.createTemp('stock-service-cn-');
  final envFile = File('${envDir.path}/.env');
  await envFile.writeAsString('');
  ConfigService.instance.resetForTest();
  ConfigService.instance.setBuildFlavorOverrideForTest(AppFlavor.cn);
  ConfigService.instance.setCompileTimeEnvOverrideForTest({
    'ZHITU_API_TOKEN': '',
  });
  await ConfigService.instance.loadFromPath(envFile.path);

  final profile = AppProfileService(prefs);
  await profile.ensureInitialized(deviceLocale: const Locale('zh', 'CN'));
  GetIt.instance.registerSingleton<AppProfileService>(profile);
  GetIt.instance.registerLazySingleton<CloudService>(() => CloudService());

  return StockService(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CN stock search builds a local fallback cache without Zhitu token',
    () async {
      final service = await _loadCnStockService();

      expect(service.canSearchStocks, isTrue);
      expect(service.canRefreshQuotes, isFalse);
      expect(service.isProviderReady, isFalse);

      final cache = await service.ensureSearchCache();
      expect(cache, isNotEmpty);
      expect(service.searchCacheUpdatedAtMs, isNotNull);

      final result = await service.searchStocks('茅台');
      expect(result.single.pureCode, '600519');
      expect(result.single.exchange, 'SH');
    },
  );
}
