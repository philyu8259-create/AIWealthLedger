import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/entities.dart';
import '../models/account_entry_model.dart';
import 'i_account_entry_datasource.dart';

/// 本地 Mock 数据源（SharedPreferences 持久化）
/// 实现 IAccountEntryDataSource 接口
class MockAccountEntryDataSource implements IAccountEntryDataSource {
  static const _storageKey = 'account_entries';
  final SharedPreferences _prefs;

  MockAccountEntryDataSource(this._prefs);

  @override
  Future<List<AccountEntry>> getEntries() async {
    debugPrint('[MockDataSource] getEntries() called');
    // 直接内联生成硬编码示例数据（不调用其他方法，避免作用域问题）
    final now = DateTime.now();
    final entries = <AccountEntry>[
      AccountEntryModel(
        id: 'd1',
        amount: 45.0,
        type: EntryType.expense,
        category: 'food',
        description: '午餐',
        date: DateTime(2026, 3, 1),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
      AccountEntryModel(
        id: 'd2',
        amount: 128.5,
        type: EntryType.expense,
        category: 'transport',
        description: '打车',
        date: DateTime(2026, 3, 2),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
      AccountEntryModel(
        id: 'd3',
        amount: 8000.0,
        type: EntryType.income,
        category: 'salary',
        description: '月薪',
        date: DateTime(2026, 3, 3),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
      AccountEntryModel(
        id: 'd4',
        amount: 23.0,
        type: EntryType.expense,
        category: 'food',
        description: '早餐',
        date: DateTime(2026, 3, 4),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
      AccountEntryModel(
        id: 'd5',
        amount: 56.0,
        type: EntryType.expense,
        category: 'daily',
        description: '超市',
        date: DateTime(2026, 3, 5),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
      AccountEntryModel(
        id: 'd6',
        amount: 88.0,
        type: EntryType.expense,
        category: 'entertainment',
        description: '电影',
        date: DateTime(2026, 3, 6),
        createdAt: now,
        syncStatus: SyncStatus.synced,
      ),
    ];
    debugPrint(
      '[MockDataSource] getEntries() returning ${entries.length} hardcoded entries',
    );
    return entries;
  }

  @override
  Future<List<AccountEntry>> getEntriesByMonth(int year, int month) async {
    final all = await getEntries();
    return all
        .where((e) => e.date.year == year && e.date.month == month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<AccountEntry> addEntry(AccountEntry entry) async {
    final all = await getEntries();
    final model = AccountEntryModel.fromEntity(entry);
    all.insert(0, model);
    await _save(all);
    return model;
  }

  @override
  Future<AccountEntry> updateEntry(AccountEntry entry) async {
    final all = await getEntries();
    final idx = all.indexWhere((e) => e.id == entry.id);
    if (idx < 0) throw Exception('Entry not found: ${entry.id}');
    final model = AccountEntryModel.fromEntity(entry);
    all[idx] = model;
    await _save(all);
    return model;
  }

  @override
  Future<void> deleteEntry(String id) async {
    final all = await getEntries();
    all.removeWhere((e) => e.id == id);
    await _save(all);
  }

  Future<void> _save(List<AccountEntry> entries) async {
    final jsonList = entries.map((e) => e.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }


  @override
  Future<List<AccountEntry>> restoreFromCloudIfNeeded() async => [];

  @override
  String? getCurrentPhone() => null;

  @override
  bool isDemoAccount() => false;
}
