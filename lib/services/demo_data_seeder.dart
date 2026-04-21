import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_flavor.dart';
import 'app_profile_service.dart';

enum DemoDataVariant { cn, intl }

/// Demo 数据填充器
/// 当 Demo 账号登录时，写入示例数据到 SharedPreferences
class DemoDataSeeder {
  static const _demoEntriesKey = 'demo_accounting_entries';
  static const _demoAccountsKey = 'demo_asset_accounts';
  static const _demoBudgetsKey = 'demo_budgets';
  static const _demoStockPositionsKey = 'demo_stock_positions_v1';
  static const _lastQuoteRefreshMsKey = 'stock_last_quote_refresh_ms_v1';
  static const _lastManualRefreshMsKey = 'stock_last_manual_refresh_ms_v1';
  static const _lastAutoSlotKey = 'stock_last_auto_slot_v1';
  static const _isSeededKey = 'demo_data_seeded';
  static const _seededVariantKey = 'demo_data_seeded_variant';

  static SharedPreferences get _prefs => GetIt.instance<SharedPreferences>();

  static DemoDataVariant get _currentVariant {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl
          ? DemoDataVariant.intl
          : DemoDataVariant.cn;
    }
    return AppFlavorX.current.isIntl ? DemoDataVariant.intl : DemoDataVariant.cn;
  }

  /// 检查当前变体的 Demo 数据是否已填充过
  static Future<bool> isAlreadySeeded({DemoDataVariant? variant}) async {
    final target = variant ?? _currentVariant;
    final seededVariant = _prefs.getString(_seededVariantKey);
    if (seededVariant != null && seededVariant == target.name) {
      return true;
    }

    // 兼容老版本：仅中文 Demo 曾经只有 bool 标记
    if (target == DemoDataVariant.cn) {
      return _prefs.getBool(_isSeededKey) ?? false;
    }
    return false;
  }

  /// 填充示例数据（仅在当前变体未填充时执行一次）
  static Future<void> seedIfNeeded({DemoDataVariant? variant}) async {
    final target = variant ?? _currentVariant;
    if (await isAlreadySeeded(variant: target)) return;
    await seed(variant: target);
  }

  /// 执行数据填充
  static Future<void> seed({DemoDataVariant? variant}) async {
    final target = variant ?? _currentVariant;
    switch (target) {
      case DemoDataVariant.cn:
        await _seedCn();
        return;
      case DemoDataVariant.intl:
        await _seedIntl();
        return;
    }
  }

  static Future<void> _seedCn() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final twoDaysAgo = DateTime(now.year, now.month, now.day - 2);

    final demoAccounts = [
      _assetJson('a1', '现金', 'cash', 5000.0, today, description: '随身备用'),
      _assetJson('a2', '招商银行', 'bank', 12500.0, today, description: '储蓄卡'),
      _assetJson('a3', '货币基金', 'fund', 15800.0, today, description: '稳健理财'),
      _assetJson('a4', '应急备用金', 'other', 20000.0, today, description: '家庭紧急预备'),
    ];

    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);
    final lmDay5 = DateTime(lastMonth.year, lastMonth.month, 5);
    final lmDay10 = DateTime(lastMonth.year, lastMonth.month, 10);
    final lmDay15 = DateTime(lastMonth.year, lastMonth.month, 15);
    final lmDay20 = DateTime(lastMonth.year, lastMonth.month, 20);

    final demoEntries = [
      _entryJson('e1', 'a1', 'expense', 45.0, 'food', '午餐', today),
      _entryJson('e2', 'a2', 'expense', 128.5, 'transport', '打车', today),
      _entryJson('e3', 'a3', 'expense', 299.0, 'shopping', '日用品', today),
      _entryJson('e4', 'a2', 'income', 8000.0, 'salary', '月薪', today),
      _entryJson('e5', 'a1', 'expense', 23.0, 'food', '早餐', yesterday),
      _entryJson('e6', 'a2', 'expense', 56.0, 'daily', '超市', yesterday),
      _entryJson('e7', 'a4', 'expense', 88.0, 'entertainment', '电影', yesterday),
      _entryJson('e8', 'a3', 'expense', 15.0, 'food', '奶茶', twoDaysAgo),
      _entryJson('e9', 'a4', 'expense', 200.0, 'clothing', '衣服', twoDaysAgo),
      _entryJson('e10', 'a1', 'income', 500.0, 'gift', '红包', twoDaysAgo),
      _entryJson('e11', 'a1', 'expense', 35.0, 'food', '午餐', lmDay5),
      _entryJson('e12', 'a2', 'expense', 85.0, 'transport', '地铁', lmDay5),
      _entryJson('e13', 'a3', 'expense', 156.0, 'shopping', '衣服', lmDay10),
      _entryJson('e14', 'a2', 'income', 3000.0, 'salary', '兼职', lmDay10),
      _entryJson('e15', 'a1', 'expense', 220.0, 'food', '朋友聚餐', lmDay15),
      _entryJson('e16', 'a2', 'expense', 580.0, 'digital', '电子产品', lmDay15),
      _entryJson('e17', 'a4', 'expense', 99.0, 'entertainment', '会员订阅', lmDay20),
      _entryJson('e18', 'a3', 'expense', 45.0, 'food', '下午茶', lastMonthEnd),
      _entryJson('e19', 'a2', 'expense', 180.0, 'transport', '打车', lastMonthEnd),
      _entryJson('e20', 'a1', 'income', 200.0, 'refund', '退款', lastMonthEnd),
    ];

    final demoBudgets = [
      {
        'id': 'b1',
        'category': 'food',
        'amount': 2000.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'b2',
        'category': 'transport',
        'amount': 800.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'b3',
        'category': 'shopping',
        'amount': 1500.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'b4',
        'category': 'entertainment',
        'amount': 500.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
    ];

    final demoStocks = [
      _stockJson(
        id: 's1',
        code: '600519',
        name: '贵州茅台',
        exchange: 'SH',
        quantity: 100,
        costPrice: 1468.0,
        latestPrice: 1526.8,
        changePercent: 1.82,
        quoteUpdatedAt: today.add(const Duration(hours: 15, minutes: 5)),
        createdAt: lmDay10,
        updatedAt: today.add(const Duration(hours: 15, minutes: 5)),
      ),
      _stockJson(
        id: 's2',
        code: '000001',
        name: '平安银行',
        exchange: 'SZ',
        quantity: 800,
        costPrice: 10.82,
        latestPrice: 11.36,
        changePercent: 2.07,
        quoteUpdatedAt: today.add(const Duration(hours: 15, minutes: 5)),
        createdAt: lmDay20,
        updatedAt: today.add(const Duration(hours: 15, minutes: 5)),
      ),
    ];

    await _writeSeededData(
      variant: DemoDataVariant.cn,
      demoAccounts: demoAccounts,
      demoEntries: demoEntries,
      demoBudgets: demoBudgets,
      demoStocks: demoStocks,
    );
  }

  static Future<void> _seedIntl() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final twoDaysAgo = DateTime(now.year, now.month, now.day - 2);

    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0);
    final lmDay4 = DateTime(lastMonth.year, lastMonth.month, 4);
    final lmDay9 = DateTime(lastMonth.year, lastMonth.month, 9);
    final lmDay14 = DateTime(lastMonth.year, lastMonth.month, 14);
    final lmDay21 = DateTime(lastMonth.year, lastMonth.month, 21);

    final demoAccounts = [
      _assetJson(
        'us_a1',
        'Wallet',
        'cash',
        420.0,
        today,
        description: 'Cash on hand',
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _assetJson(
        'us_a2',
        'Chase Checking',
        'bank',
        3850.0,
        today,
        description: 'Main spending account',
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _assetJson(
        'us_a3',
        'Emergency Fund',
        'fund',
        6800.0,
        today,
        description: 'High-yield savings',
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _assetJson(
        'us_a4',
        'Travel Budget',
        'other',
        1200.0,
        today,
        description: 'Summer trip savings',
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
    ];

    final demoEntries = [
      _entryJson(
        'us_e1',
        'us_a2',
        'expense',
        18.5,
        'food',
        'Coffee and breakfast',
        today,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e2',
        'us_a2',
        'expense',
        42.0,
        'transport',
        'Rideshare to downtown',
        today,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e3',
        'us_a2',
        'expense',
        79.9,
        'shopping',
        'Household supplies',
        today,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e4',
        'us_a2',
        'income',
        2450.0,
        'salary',
        'Biweekly paycheck',
        today,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e5',
        'us_a1',
        'expense',
        12.0,
        'food',
        'Sandwich lunch',
        yesterday,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e6',
        'us_a2',
        'expense',
        64.3,
        'daily',
        'Groceries',
        yesterday,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e7',
        'us_a4',
        'expense',
        26.0,
        'entertainment',
        'Movie tickets',
        yesterday,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e8',
        'us_a2',
        'expense',
        15.5,
        'food',
        'Afternoon coffee',
        twoDaysAgo,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e9',
        'us_a2',
        'expense',
        120.0,
        'clothing',
        'Running shoes',
        twoDaysAgo,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e10',
        'us_a1',
        'income',
        80.0,
        'gift',
        'Birthday gift',
        twoDaysAgo,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e11',
        'us_a1',
        'expense',
        14.0,
        'food',
        'Lunch bowl',
        lmDay4,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e12',
        'us_a2',
        'expense',
        31.0,
        'transport',
        'Train pass',
        lmDay4,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e13',
        'us_a2',
        'expense',
        210.0,
        'shopping',
        'Home office gear',
        lmDay9,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e14',
        'us_a2',
        'income',
        2450.0,
        'salary',
        'Biweekly paycheck',
        lmDay9,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e15',
        'us_a2',
        'expense',
        95.0,
        'food',
        'Dinner with friends',
        lmDay14,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e16',
        'us_a2',
        'expense',
        349.0,
        'digital',
        'Tablet accessory',
        lmDay14,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e17',
        'us_a4',
        'expense',
        14.99,
        'entertainment',
        'Streaming subscription',
        lmDay21,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e18',
        'us_a2',
        'expense',
        23.0,
        'food',
        'Weekend brunch',
        lastMonthEnd,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e19',
        'us_a2',
        'expense',
        58.0,
        'transport',
        'Airport shuttle',
        lastMonthEnd,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _entryJson(
        'us_e20',
        'us_a2',
        'income',
        35.0,
        'refund',
        'Returned order refund',
        lastMonthEnd,
        currency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
    ];

    final demoBudgets = [
      {
        'id': 'us_b1',
        'category': 'food',
        'amount': 650.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'us_b2',
        'category': 'transport',
        'amount': 280.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'us_b3',
        'category': 'shopping',
        'amount': 450.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
      {
        'id': 'us_b4',
        'category': 'entertainment',
        'amount': 180.0,
        'month': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      },
    ];

    final quoteTime = today.add(const Duration(hours: 16, minutes: 5));
    final demoStocks = [
      _stockJson(
        id: 'us_s1',
        code: 'AAPL',
        name: 'Apple',
        exchange: 'US',
        quantity: 12,
        costPrice: 198.4,
        latestPrice: 211.3,
        changePercent: 1.24,
        quoteUpdatedAt: quoteTime,
        createdAt: lmDay9,
        updatedAt: quoteTime,
        marketCurrency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
      _stockJson(
        id: 'us_s2',
        code: 'MSFT',
        name: 'Microsoft',
        exchange: 'US',
        quantity: 8,
        costPrice: 412.6,
        latestPrice: 426.1,
        changePercent: 0.96,
        quoteUpdatedAt: quoteTime,
        createdAt: lmDay21,
        updatedAt: quoteTime,
        marketCurrency: 'USD',
        locale: 'en-US',
        countryCode: 'US',
      ),
    ];

    await _writeSeededData(
      variant: DemoDataVariant.intl,
      demoAccounts: demoAccounts,
      demoEntries: demoEntries,
      demoBudgets: demoBudgets,
      demoStocks: demoStocks,
    );
  }

  static Future<void> _writeSeededData({
    required DemoDataVariant variant,
    required List<Map<String, dynamic>> demoAccounts,
    required List<Map<String, dynamic>> demoEntries,
    required List<Map<String, dynamic>> demoBudgets,
    required List<Map<String, dynamic>> demoStocks,
  }) async {
    await _prefs.setString(_demoAccountsKey, jsonEncode(demoAccounts));
    await _prefs.setString(_demoEntriesKey, jsonEncode(demoEntries));
    await _prefs.setString(_demoBudgetsKey, jsonEncode(demoBudgets));
    await _prefs.setString(_demoStockPositionsKey, jsonEncode(demoStocks));
    await _prefs.remove(_lastQuoteRefreshMsKey);
    await _prefs.remove(_lastManualRefreshMsKey);
    await _prefs.remove(_lastAutoSlotKey);
    await _prefs.setBool(_isSeededKey, true);
    await _prefs.setString(_seededVariantKey, variant.name);

    final verify = _prefs.getString(_demoEntriesKey);
    debugPrint(
      '[DemoDataSeeder] seed(${variant.name}) 完成，写入key=$_demoEntriesKey，验证=${verify == null ? "null" : "exists(${verify.length})"}',
    );
    debugPrint(
      '[DemoDataSeeder] seed(${variant.name}) 共 ${demoEntries.length} 条记账记录，${demoAccounts.length} 个账户',
    );
  }

  static Map<String, dynamic> _assetJson(
    String id,
    String name,
    String type,
    double balance,
    DateTime date, {
    String? description,
    String currency = 'CNY',
    String locale = 'zh-CN',
    String countryCode = 'CN',
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'balance': balance,
      'currency': currency,
      'locale': locale,
      'countryCode': countryCode,
      'createdAt': date.millisecondsSinceEpoch,
      'syncStatus': 'synced',
      ...?(description == null ? null : {'description': description}),
    };
  }

  static Map<String, dynamic> _entryJson(
    String id,
    String assetId,
    String type,
    double amount,
    String category,
    String note,
    DateTime date, {
    String currency = 'CNY',
    String locale = 'zh-CN',
    String countryCode = 'CN',
  }) {
    return {
      'id': id,
      'assetId': assetId,
      'type': type,
      'amount': amount,
      'category': category,
      'description': note,
      'date': date.millisecondsSinceEpoch,
      'createdAt': date.millisecondsSinceEpoch,
      'syncStatus': 'synced',
      'originalAmount': amount,
      'originalCurrency': currency,
      'baseAmount': amount,
      'baseCurrency': currency,
      'fxRate': 1.0,
      'fxRateSource': 'demo',
      'sourceType': 'manual',
      'locale': locale,
      'countryCode': countryCode,
    };
  }

  static Map<String, dynamic> _stockJson({
    required String id,
    required String code,
    required String name,
    required String exchange,
    required int quantity,
    required double costPrice,
    required double latestPrice,
    required double changePercent,
    required DateTime quoteUpdatedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? marketCurrency,
    String? locale,
    String? countryCode,
  }) {
    return {
      'id': id,
      'assetType': 'stock',
      'code': code,
      'name': name,
      'exchange': exchange,
      'quantity': quantity,
      'costPrice': costPrice,
      'latestPrice': latestPrice,
      'changePercent': changePercent,
      ...?(marketCurrency == null ? null : {'marketCurrency': marketCurrency}),
      ...?(locale == null ? null : {'locale': locale}),
      ...?(countryCode == null ? null : {'countryCode': countryCode}),
      'quoteUpdatedAt': quoteUpdatedAt.toIso8601String(),
      'quoteStatus': 'normal',
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 清除 Demo 数据（切换到真实用户时调用）
  static Future<void> clear() async {
    await _prefs.remove(_demoEntriesKey);
    await _prefs.remove(_demoAccountsKey);
    await _prefs.remove(_demoBudgetsKey);
    await _prefs.remove(_demoStockPositionsKey);
    await _prefs.remove(_lastQuoteRefreshMsKey);
    await _prefs.remove(_lastManualRefreshMsKey);
    await _prefs.remove(_lastAutoSlotKey);
    await _prefs.remove(_seededVariantKey);
    await _prefs.setBool(_isSeededKey, false);
  }

  /// 获取 Demo 记账记录（供 mock datasource 读取）
  static Future<List<Map<String, dynamic>>> getDemoEntries() async {
    final raw = _prefs.getString(_demoEntriesKey);
    debugPrint(
      '[DemoDataSeeder] getDemoEntries() raw=${raw == null ? "null" : "exists(${raw.length})"}',
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      debugPrint('[DemoDataSeeder] getDemoEntries() decoded ${list.length} items');
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('[DemoDataSeeder] getDemoEntries() decode error: $e');
      return [];
    }
  }

  /// 获取 Demo 资产账户
  static Future<List<Map<String, dynamic>>> getDemoAccounts() async {
    final raw = _prefs.getString(_demoAccountsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 获取 Demo 预算
  static Future<List<Map<String, dynamic>>> getDemoBudgets() async {
    final raw = _prefs.getString(_demoBudgetsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
