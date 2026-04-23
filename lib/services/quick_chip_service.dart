import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 快捷记账类目配置服务
/// 存储用户自定义的快捷类目列表（category id 列表）
class QuickChipService {
  static const _key =
      'quick_chip_service_ids'; // 避免与 MockCustomCategoryDataSource 的 'quick_chip_ids' 冲突
  static const _defaultIds = [
    'food',
    'transport',
    'shopping',
    'housing',
    'grocery',
    'daily',
  ];
  static const _legacyDefaultIds = [
    'food',
    'transport',
    'shopping',
    'entertainment',
    'housing',
    'coffee',
    'fruit',
    'grocery',
    'daily',
  ];

  final SharedPreferences _prefs;

  QuickChipService(this._prefs);

  /// 获取用户配置的快捷类目 ID 列表
  List<String> getIds() {
    final saved = _prefs.getString(_key);
    if (saved == null || saved.isEmpty) return List.from(_defaultIds);
    try {
      final list = jsonDecode(saved) as List<dynamic>;
      final ids = list.cast<String>();
      if (_matchesLegacyDefaults(ids)) {
        return List.from(_defaultIds);
      }
      return ids;
    } catch (_) {
      return List.from(_defaultIds);
    }
  }

  bool _matchesLegacyDefaults(List<String> ids) {
    if (ids.length != _legacyDefaultIds.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != _legacyDefaultIds[i]) return false;
    }
    return true;
  }

  /// 保存快捷类目 ID 列表
  Future<void> saveIds(List<String> ids) async {
    await _prefs.setString(_key, jsonEncode(ids));
  }

  /// 添加一个类目到快捷栏（自动去重）
  Future<List<String>> addId(String id) async {
    final ids = getIds();
    if (!ids.contains(id)) {
      ids.add(id);
      await saveIds(ids);
    }
    return ids;
  }

  /// 从快捷栏移除一个类目
  Future<List<String>> removeId(String id) async {
    final ids = getIds();
    ids.remove(id);
    await saveIds(ids);
    return ids;
  }
}
