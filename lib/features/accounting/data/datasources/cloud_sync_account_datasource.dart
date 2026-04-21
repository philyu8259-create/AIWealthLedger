import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../services/app_profile_service.dart';
import '../../domain/entities/entities.dart';
import 'i_account_entry_datasource.dart';
import '../../../../services/cloud_service.dart';

class CloudSyncAccountDataSource implements IAccountEntryDataSource {
  final SharedPreferences _prefs;
  static const _storageKey = 'account_entries';
  static const _demoStorageKey = 'demo_accounting_entries';

  AppProfileService get _profile => GetIt.instance<AppProfileService>();

  CloudSyncAccountDataSource(this._prefs);

  /// 登录后从云端恢复数据（仅当本地为空时）
  @override
  Future<List<AccountEntry>> restoreFromCloudIfNeeded() async {
    final phone = _prefs.getString('logged_in_phone');
    debugPrint('[CloudSync] restoreFromCloud: phone=$phone');
    if (phone == null || phone.isEmpty || phone == 'DemoAccount') {
      debugPrint('[CloudSync] restoreFromCloud: skip (游客/Demo)');
      return [];
    }
    try {
      debugPrint(
        '[CloudSync] restoreFromCloud: calling CloudService.getEntries()...',
      );
      final cloudEntries = await CloudService().getEntries();
      debugPrint(
        '[CloudSync] restoreFromCloud: got ${cloudEntries.length} from cloud',
      );

      // 读取本地所有数据
      final localData = _prefs.getString(_storageKey);
      List<Map<String, dynamic>> localList = [];
      if (localData != null && localData.isNotEmpty) {
        try {
          localList = (jsonDecode(localData) as List)
              .cast<Map<String, dynamic>>();
          debugPrint(
            '[CloudSync] restoreFromCloud: local has ${localList.length} items',
          );
        } catch (_) {
          localList = [];
        }
      }

      // 内容去重 key: createdAt(完整时间戳) + amount + type + category
      // 使用 createdAt 而非 date，确保同一天同一时刻的两条相同账单都能保留
      String contentKey(Map<String, dynamic> e) {
        final createdAtVal = e['createdAt'];
        int createdAtMs;
        if (createdAtVal is int) {
          createdAtMs = createdAtVal;
        } else if (createdAtVal is String) {
          createdAtMs = DateTime.parse(createdAtVal).millisecondsSinceEpoch;
        } else {
          createdAtMs = (createdAtVal as DateTime).millisecondsSinceEpoch;
        }
        return '${createdAtMs}_${e['amount']}_${e['type']}_${e['category']}';
      }

      final cloudMap = <String, Map<String, dynamic>>{};
      for (final e in cloudEntries) {
        final key = contentKey(e);
        cloudMap[key] = Map<String, dynamic>.from(e);
      }

      // 转换为本地 map（用于优先保留本地数据）
      final localMap = <String, Map<String, dynamic>>{};
      for (final e in localList) {
        final key = contentKey(e);
        localMap[key] = Map<String, dynamic>.from(e);
      }

      final mergedMap = <String, Map<String, dynamic>>{};
      // 【修复】本地优先：先加入全部本地条目，永不覆盖
      mergedMap.addAll(localMap);

      // 再加入云端条目：云端有但本地没有的才补充（本地没有的数据才需要从云端恢复）
      for (final e in cloudEntries) {
        final key = contentKey(e);
        if (!mergedMap.containsKey(key)) {
          mergedMap[key] = Map<String, dynamic>.from(e);
        }
      }

      final merged = mergedMap.values.toList();
      debugPrint(
        '[CloudSync] restoreFromCloud: merged ${merged.length} entries (cloud补充=${cloudEntries.length}, local保留=${localList.length})',
      );

      // 写回本地
      await _prefs.setString(_storageKey, jsonEncode(merged));
      debugPrint('[CloudSync] restoreFromCloud: saved to local');

      // 返回合并后的完整列表（用 AccountEntry.fromJson 正确解析 syncStatus）
      return merged.map((e) => AccountEntry.fromJson(e)).toList();
    } catch (e, st) {
      debugPrint('[CloudSync] restoreFromCloud error: $e\n$st');
      // 云端失败时 fallback 到本地数据，避免用户数据丢失
      final localData = _prefs.getString(_storageKey);
      if (localData != null && localData.isNotEmpty) {
        try {
          final decoded = jsonDecode(localData) as List;
          debugPrint(
            '[CloudSync] restoreFromCloud: falling back to local ${decoded.length} entries',
          );
          return decoded
              .map((e) => _fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {
          // 本地数据也损坏，返回空
        }
      }
      return [];
    }
  }

  @override
  Future<List<AccountEntry>> getEntries() async {
    final phone = _prefs.getString('logged_in_phone');
    debugPrint('[CloudSync] getEntries called, phone=$phone');

    // Demo 账号：只读本地
    if (phone == 'DemoAccount') {
      final key = _demoStorageKey;
      final jsonStr = _prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr) as List;
          return decoded
              .map((e) => _fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {
          await _prefs.remove(key);
        }
      }
      return [];
    }

    // 已登录用户：先读本地，再判断是否需要合并云端（避免本地pending条目被覆盖）
    final localJson = _prefs.getString(_storageKey);
    List<Map<String, dynamic>> localList = [];
    if (localJson != null && localJson.isNotEmpty) {
      try {
        localList = (jsonDecode(localJson) as List)
            .cast<Map<String, dynamic>>();
      } catch (_) {
        localList = [];
      }
    }

    if (phone != null && phone.isNotEmpty) {
      // 如果本地是空的，才去云端拉（首次登录）
      if (localList.isEmpty) {
        return restoreFromCloudIfNeeded();
      } else {
        // 本地有数据，直接返回本地数据（避免本地pending条目被覆盖）
        // 只有登录时才去云端合并，日常读数据优先用本地
        return localList.map((e) => _fromJson(e)).toList();
      }
    }

    // 未登录用户：只读本地
    return localList.map((e) => _fromJson(e)).toList();
  }

  @override
  String? getCurrentPhone() {
    final phone = _prefs.getString('logged_in_phone');
    if (phone == null || phone.isEmpty || phone == 'DemoAccount') return null;
    return phone;
  }

  @override
  bool isDemoAccount() {
    final phone = _prefs.getString('logged_in_phone');
    return phone == 'DemoAccount';
  }

  @override
  Future<List<AccountEntry>> getEntriesByMonth(int year, int month) async {
    final all = await getEntries();
    return all
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();
  }

  @override
  Future<AccountEntry> addEntry(AccountEntry entry) async {
    final phone = _prefs.getString('logged_in_phone');
    final isDemo = phone == 'DemoAccount';
    debugPrint(
      '[CloudSync] addEntry BEGIN, phone=$phone, isDemo=$isDemo, entry.id=${entry.id}',
    );

    // 写入本地（初始为 pending）
    try {
      final all = await getEntries();
      debugPrint(
        '[CloudSync] addEntry getEntries returned ${all.length}, inserting new entry',
      );
      all.insert(0, entry);
      await _saveAll(all, forDemo: isDemo);
      debugPrint(
        '[CloudSync] addEntry _saveAll done (pending), count=${all.length}',
      );
    } catch (e) {
      debugPrint('[CloudSync] addEntry getEntries failed: $e, saving single entry');
      await _saveAll([entry], forDemo: isDemo);
    }

    // 云端写入（已登录用户）
    if (phone != null && phone.isNotEmpty) {
      try {
        final result = await CloudService().addEntry(entry);
        debugPrint('[CloudSync] addEntry cloud result: $result');
        // 云端成功返回（不区分 body 内容），更新本地 syncStatus 为 synced
        if (result != null) {
          final all = await getEntries();
          final idx = all.indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            final synced = all[idx].copyWith(syncStatus: SyncStatus.synced);
            all[idx] = synced;
            await _saveAll(all, forDemo: isDemo);
            debugPrint('[CloudSync] addEntry updated local syncStatus=synced');
            return synced; // 返回同步后的条目
          }
        }
      } catch (e) {
        debugPrint('[CloudSync] addEntry cloud FAILED: $e');
      }
    }
    return entry;
  }

  @override
  Future<AccountEntry> updateEntry(AccountEntry entry) async {
    final phone = _prefs.getString('logged_in_phone');
    final isDemo = phone == 'DemoAccount';

    // 更新本地 — getEntries 失败也要保证本地更新完成
    try {
      final all = await getEntries();
      final idx = all.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) {
        all[idx] = entry;
        await _saveAll(all, forDemo: isDemo);
      }
    } catch (e) {
      debugPrint('[CloudSyncAccountDataSource] updateEntry getEntries failed: $e');
    }

    // 已登录用户：同时更新云端（失败不影响本地）
    if (phone != null && phone.isNotEmpty) {
      try {
        await CloudService().updateEntry(entry);
      } catch (e) {
        debugPrint(
          '[CloudSyncAccountDataSource] cloud updateEntry failed (non-fatal): $e',
        );
      }
    }
    return entry;
  }

  /// 标记条目为已删除（用于多设备同步时过滤云端旧数据）
  Future<void> _markAsDeleted(String id) async {
    final deleted = _prefs.getStringList('_deletedEntryIds') ?? [];
    if (!deleted.contains(id)) {
      deleted.add(id);
      await _prefs.setStringList('_deletedEntryIds', deleted);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    final phone = _prefs.getString('logged_in_phone');
    final isDemo = phone == 'DemoAccount';

    // 记录为已删除，防止云端旧数据覆盖
    await _markAsDeleted(id);

    // 删除本地 — getEntries 失败也要保证本地删除完成
    try {
      final all = await getEntries();
      all.removeWhere((e) => e.id == id);
      await _saveAll(all, forDemo: isDemo);
    } catch (e) {
      debugPrint('[CloudSyncAccountDataSource] deleteEntry getEntries failed: $e');
    }

    // 已登录用户：同时删除云端（失败不影响本地）
    if (phone != null && phone.isNotEmpty) {
      try {
        await CloudService().deleteEntry(id);
      } catch (e) {
        debugPrint(
          '[CloudSyncAccountDataSource] cloud deleteEntry failed (non-fatal): $e',
        );
      }
      // 注意：不在此处调用 restoreFromCloudIfNeeded()
      // FC 删除是异步的，调用后立即拉取会导致已删除的条目被重新写回本地
      // 设备 B 下次打开 App 时会自然触发 restoreFromCloudIfNeeded（通过 login page）
      // 或通过 AppLifecycleState.resumed -> LoadCurrentMonthEntries 刷新
    }
  }

  Future<void> _saveAll(
    List<AccountEntry> entries, {
    bool forDemo = false,
  }) async {
    final jsonList = entries
        .map(
          (e) => {
            'id': e.id,
            'type': e.type == EntryType.income ? 'income' : 'expense',
            'amount': e.amount,
            'category': e.category,
            'description': e.description,
            'date': e.date.millisecondsSinceEpoch,
            'createdAt': e.createdAt.millisecondsSinceEpoch,
            'syncStatus': e.syncStatus == SyncStatus.synced
                ? 'synced'
                : (e.syncStatus == SyncStatus.failed ? 'failed' : 'pending'),
          },
        )
        .toList();
    final key = forDemo ? _demoStorageKey : _storageKey;
    debugPrint(
      '[CloudSyncAccountDataSource] _saveAll to key=$key, count=${entries.length}',
    );
    await _prefs.setString(key, jsonEncode(jsonList));
  }


  AccountEntry _fromJson(Map<String, dynamic> json) {
    final entry = AccountEntry.fromJson(json);
    final profile = _profile.currentProfile.localeProfile;
    final hasOriginalCurrency = (json['originalCurrency'] as String?)?.isNotEmpty == true;
    final hasBaseCurrency = (json['baseCurrency'] as String?)?.isNotEmpty == true;
    final hasLocale = (json['locale'] as String?)?.isNotEmpty == true;
    final hasCountryCode = (json['countryCode'] as String?)?.isNotEmpty == true;

    if (hasOriginalCurrency && hasBaseCurrency && hasLocale && hasCountryCode) {
      return entry;
    }

    return entry.copyWith(
      originalCurrency: hasOriginalCurrency
          ? entry.originalCurrency
          : profile.baseCurrency,
      baseCurrency: hasBaseCurrency ? entry.baseCurrency : profile.baseCurrency,
      locale: hasLocale ? entry.locale : profile.localeTag.replaceAll('_', '-'),
      countryCode: hasCountryCode ? entry.countryCode : profile.countryCode,
    );
  }

}
