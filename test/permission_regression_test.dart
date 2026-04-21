import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_accounting_app/services/vip_service.dart';

import 'package:ai_accounting_app/features/accounting/data/datasources/cloud_asset_datasource.dart';
import 'package:ai_accounting_app/features/accounting/domain/entities/entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
  });

  test('guest should not read demo assets by mistake', () async {
    final prefs = GetIt.instance<SharedPreferences>();
    await prefs.setString(
      'demo_asset_accounts',
      jsonEncode([
        {
          'id': 'demo-1',
          'name': '演示资产',
          'type': 'cash',
          'balance': 100.0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        }
      ]),
    );

    final dataSource = CloudAssetDataSource();
    final assets = await dataSource.getAssets();

    expect(assets, isEmpty);
  });

  test('guest asset add should stay local and be readable', () async {
    final dataSource = CloudAssetDataSource();
    final created = await dataSource.addAsset(
      Asset(
        id: '',
        name: '现金',
        type: AssetType.cash,
        balance: 88,
        createdAt: DateTime.now(),
      ),
    );

    final assets = await dataSource.getAssets();
    expect(created.id, isNotEmpty);
    expect(assets.length, 1);
    expect(assets.first.name, '现金');
  });

  test('guest should not be treated as expired vip user', () async {
    expect(
      shouldTreatAsExpiredEntitlement(phone: null, expireMs: 0),
      isFalse,
    );
  });

  test('demo account should not be treated as expired vip user', () async {
    expect(
      shouldTreatAsExpiredEntitlement(
        phone: 'DemoAccount',
        expireMs: DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ),
      isFalse,
    );
  });

  test('normal logged-in non-vip user should not be treated as expired', () async {
    expect(
      shouldTreatAsExpiredEntitlement(phone: '13800138000', expireMs: 0),
      isFalse,
    );
  });

  test('only real user with expired vip cache should be treated as expired', () async {
    expect(
      shouldTreatAsExpiredEntitlement(
        phone: '13800138000',
        expireMs: DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ),
      isTrue,
    );
  });
}
