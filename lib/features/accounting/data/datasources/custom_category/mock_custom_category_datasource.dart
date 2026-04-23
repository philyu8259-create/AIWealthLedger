import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/custom_category/custom_category.dart';
import 'i_custom_category_datasource.dart';

class MockCustomCategoryDataSource implements ICustomCategoryDataSource {
  static const _storageKey = 'custom_categories';
  static const _defaultQuickChipIds = [
    'food',
    'transport',
    'shopping',
    'housing',
    'grocery',
    'daily',
  ];
  static const _legacyQuickChipIds = [
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
  List<CustomCategory>? _cache;

  MockCustomCategoryDataSource(this._prefs);

  @override
  Future<List<CustomCategory>> getCustomCategories() async {
    if (_cache != null) return _cache!;

    final jsonStr = _prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      _cache = [];
      return _cache!;
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
      _cache = jsonList
          .map((json) => CustomCategory.fromJson(json as Map<String, dynamic>))
          .toList();
      return _cache!;
    } catch (_) {
      _cache = [];
      return _cache!;
    }
  }

  @override
  Future<CustomCategory> addCustomCategory(CustomCategory category) async {
    final all = await getCustomCategories();
    all.add(category);
    _cache = all;
    await _save(all);
    return category;
  }

  @override
  Future<CustomCategory> updateCustomCategory(CustomCategory category) async {
    final all = await getCustomCategories();
    final idx = all.indexWhere((e) => e.id == category.id);
    if (idx < 0) throw Exception('Category not found: ${category.id}');
    all[idx] = category;
    _cache = all;
    await _save(all);
    return category;
  }

  @override
  Future<void> deleteCustomCategory(String id) async {
    final all = await getCustomCategories();
    all.removeWhere((e) => e.id == id);
    _cache = all;
    await _save(all);
  }

  Future<void> _save(List<CustomCategory> categories) async {
    final jsonList = categories.map((e) => e.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  static const _quickChipIdsKey = 'quick_chip_ids';

  @override
  Future<List<String>> getQuickChipIds() async {
    final ids = _prefs.getStringList(_quickChipIdsKey) ?? [];
    if (_matchesLegacyQuickChipIds(ids)) {
      await _prefs.setStringList(_quickChipIdsKey, _defaultQuickChipIds);
      return List.from(_defaultQuickChipIds);
    }
    return ids;
  }

  @override
  Future<void> saveQuickChipIds(List<String> ids) async {
    await _prefs.setStringList(_quickChipIdsKey, ids);
  }

  bool _matchesLegacyQuickChipIds(List<String> ids) {
    if (ids.length != _legacyQuickChipIds.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != _legacyQuickChipIds[i]) return false;
    }
    return true;
  }
}
