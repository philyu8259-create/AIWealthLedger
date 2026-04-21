import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../domain/entities/entities.dart';
import '../models/asset_model.dart';
import 'i_asset_datasource.dart';

/// 本地资产账户数据源（SharedPreferences 持久化）
class MockAssetDataSource implements IAssetDataSource {
  static const _storageKey = 'assets';
  final SharedPreferences _prefs;
  List<Asset>? _cache;

  MockAssetDataSource(this._prefs);

  bool get _chinaWalletAssetsEnabled => GetIt.instance<AppProfileService>()
      .currentProfile
      .capabilityProfile
      .isEnabled('chinaWalletAssets');

  bool _isForbiddenIntlWalletType(AssetType type) {
    if (_chinaWalletAssetsEnabled) return false;
    return type == AssetType.alipay || type == AssetType.wechat;
  }

  void _assertAddAllowed(Asset asset) {
    if (_isForbiddenIntlWalletType(asset.type)) {
      throw Exception(
        'Alipay and WeChat assets are not available for new entries in the international version.',
      );
    }
  }

  void _assertUpdateAllowed(Asset incoming, Asset? existing) {
    if (!_isForbiddenIntlWalletType(incoming.type)) return;
    if (existing?.type == incoming.type) return;
    throw Exception(
      'Alipay and WeChat assets are not available for new entries in the international version.',
    );
  }

  @override
  Future<List<Asset>> getAssets() async {
    final phone = _prefs.getString('logged_in_phone');

    // Demo 账号始终优先读 Demo 数据，避免被空缓存卡住。
    if (phone == 'DemoAccount') {
      final demoAccounts = await DemoDataSeeder.getDemoAccounts();
      if (demoAccounts.isNotEmpty) {
        _cache = demoAccounts.map((json) => AssetModel.fromJson(json)).toList();
        return _cache!;
      }
    }

    if (_cache != null) return _cache!;

    final jsonStr = _prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      _cache = _getDefaultData();
      return _cache!;
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
      _cache = jsonList
          .map((json) => AssetModel.fromJson(json as Map<String, dynamic>))
          .toList();
      return _cache!;
    } catch (_) {
      _cache = _getDefaultData();
      return _cache!;
    }
  }

  @override
  Future<Asset> addAsset(Asset asset) async {
    _assertAddAllowed(asset);
    final all = await getAssets();
    final model = AssetModel.fromEntity(asset);
    all.insert(0, model);
    _cache = all;
    await _save(all);
    return model;
  }

  @override
  Future<Asset> updateAsset(Asset asset) async {
    final all = await getAssets();
    final idx = all.indexWhere((e) => e.id == asset.id);
    if (idx < 0) throw Exception('Asset not found: ${asset.id}');
    _assertUpdateAllowed(asset, all[idx]);
    final model = AssetModel.fromEntity(asset);
    all[idx] = model;
    _cache = all;
    await _save(all);
    return model;
  }

  @override
  Future<void> deleteAsset(String id) async {
    final all = await getAssets();
    all.removeWhere((e) => e.id == id);
    _cache = all;
    await _save(all);
  }

  Future<void> _save(List<Asset> assets) async {
    final jsonList = assets.map((e) => e.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  List<AssetModel> _getDefaultData() {
    // 默认无资产，用户自行添加
    return [];
  }
}
