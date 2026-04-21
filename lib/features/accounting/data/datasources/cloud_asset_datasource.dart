import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/app_flavor.dart';
import '../../../../services/app_profile_service.dart';
import '../../../../services/cloud_service.dart';
import '../../../../services/demo_data_seeder.dart';
import '../../domain/entities/entities.dart';
import '../models/asset_model.dart';
import 'i_asset_datasource.dart';

/// 云端资产账户数据源
class CloudAssetDataSource implements IAssetDataSource {
  final CloudService _cloud = CloudService();
  final SharedPreferences _prefs = GetIt.instance<SharedPreferences>();
  static const _legacyStorageKey = 'cloud_assets';
  static const _storageKeyPrefix = 'cloud_assets_v2_';
  static const _demoStorageKey = 'demo_asset_accounts';

  String? get _phone => _prefs.getString('logged_in_phone');

  String _sanitizeStorageId(String? raw) {
    if (raw == null || raw.isEmpty) return 'guest';
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  String get _activeStorageKey =>
      '$_storageKeyPrefix${_sanitizeStorageId(_phone)}';

  List<Map<String, dynamic>> _loadLocalAssets() {
    String? data = _prefs.getString(_activeStorageKey);

    // 兼容旧版本全局 key，仅迁移到当前登录用户，不迁移到 guest，避免资产串号/泄漏。
    if ((data == null || data.isEmpty) &&
        _phone != null &&
        _phone!.isNotEmpty &&
        _phone != 'DemoAccount') {
      final legacy = _prefs.getString(_legacyStorageKey);
      if (legacy != null && legacy.isNotEmpty) {
        data = legacy;
        _prefs.setString(_activeStorageKey, legacy);
        _prefs.remove(_legacyStorageKey);
      }
    }

    if (data == null || data.isEmpty) return [];
    try {
      return (jsonDecode(data) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  void _saveLocalAssets(List<Map<String, dynamic>> assets) {
    _prefs.setString(_activeStorageKey, jsonEncode(assets));
  }

  void _upsertLocalAsset(Asset asset) {
    final assets = _loadLocalAssets();
    final idx = assets.indexWhere((e) => e['id'] == asset.id);
    final json = _toJson(asset);
    if (idx >= 0) {
      assets[idx] = json;
    } else {
      assets.add(json);
    }
    _saveLocalAssets(assets);
  }

  List<Map<String, dynamic>> _loadDemoAssets() {
    final data = _prefs.getString(_demoStorageKey);
    if (data == null || data.isEmpty) return [];
    try {
      return (jsonDecode(data) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDemoAssets(List<Map<String, dynamic>> assets) async {
    await _prefs.setString(_demoStorageKey, jsonEncode(assets));
  }

  AppFlavor get _resolvedFlavor {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor;
    }
    return AppFlavorX.current;
  }

  ({String localeTag, String countryCode, String baseCurrency})
  get _fallbackLocaleConfig {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      final localeProfile = GetIt.instance<AppProfileService>()
          .currentProfile
          .localeProfile;
      return (
        localeTag: localeProfile.localeTag.replaceAll('_', '-'),
        countryCode: localeProfile.countryCode,
        baseCurrency: localeProfile.baseCurrency,
      );
    }

    final isCn = _resolvedFlavor == AppFlavor.cn;
    return (
      localeTag: isCn ? 'zh-CN' : 'en-US',
      countryCode: isCn ? 'CN' : 'US',
      baseCurrency: isCn ? 'CNY' : 'USD',
    );
  }

  AssetModel _fromJson(Map<String, dynamic> json) {
    final asset = AssetModel.fromJson(json);
    final fallback = _fallbackLocaleConfig;
    final hasCurrency = (json['currency'] as String?)?.isNotEmpty == true;
    final hasLocale = (json['locale'] as String?)?.isNotEmpty == true;
    final hasCountryCode = (json['countryCode'] as String?)?.isNotEmpty == true;

    if (hasCurrency && hasLocale && hasCountryCode) {
      return asset;
    }

    return AssetModel.fromEntity(
      asset.copyWith(
        currency: hasCurrency ? asset.currency : fallback.baseCurrency,
        locale: hasLocale ? asset.locale : fallback.localeTag,
        countryCode: hasCountryCode ? asset.countryCode : fallback.countryCode,
      ),
    );
  }

  Map<String, dynamic> _toJson(Asset asset) {
    return AssetModel.fromEntity(asset)
        .copyWith(syncStatus: SyncStatus.synced)
        .toJson();
  }

  bool get _chinaWalletAssetsEnabled {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>()
          .currentProfile
          .capabilityProfile
          .isEnabled('chinaWalletAssets');
    }
    return _resolvedFlavor == AppFlavor.cn;
  }

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
    final phone = _phone;
    final demoAssets = await DemoDataSeeder.getDemoAccounts();

    if (phone == 'DemoAccount') {
      if (demoAssets.isNotEmpty) {
        await _saveDemoAssets(demoAssets);
        return demoAssets.map(_fromJson).toList();
      }
      return _loadDemoAssets().map(_fromJson).toList();
    }

    // 游客只读自己的本地资产，不得读 Demo，也不得读其他登录用户缓存。
    if (phone == null || phone.isEmpty) {
      return _loadLocalAssets().map((e) => _fromJson(e)).toList();
    }

    try {
      final resp = await _cloud.get('/assets');
      if (resp == null || resp.isEmpty) {
        // FC 返回空 → 读本地缓存
        return _loadLocalAssets().map((e) => _fromJson(e)).toList();
      }
      final rawAssets = resp['assets'] as List? ?? [];
      final result = rawAssets
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .toList();
      // 同步到本地缓存
      _saveLocalAssets(rawAssets.cast<Map<String, dynamic>>());
      return result;
    } catch (e) {
      debugPrint('[CloudAssetDataSource] getAssets error: $e');
      // 网络失败时读本地缓存
      return _loadLocalAssets().map((e) => _fromJson(e)).toList();
    }
  }

  @override
  Future<Asset> addAsset(Asset asset) async {
    _assertAddAllowed(asset);
    final phone = _phone;

    // 游客：仅写本地，不做云同步
    if (phone == null || phone.isEmpty) {
      final newAsset = asset.copyWith(
        id: asset.id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : asset.id,
        syncStatus: SyncStatus.synced,
      );
      final assets = _loadLocalAssets();
      assets.add(_toJson(newAsset));
      _saveLocalAssets(assets);
      return newAsset;
    }

    if (phone == 'DemoAccount') {
      final assets = _loadDemoAssets();
      assets.add(_toJson(asset));
      await _saveDemoAssets(assets);
      return asset.copyWith(syncStatus: SyncStatus.synced);
    }

    final resp = await _cloud.post('/assets', body: _toJson(asset));
    debugPrint('[CloudAssetDataSource] addAsset resp=$resp');
    if (resp == null) {
      // 云端失败 → 先存本地，防止重启后丢失
      final assets = _loadLocalAssets();
      final newAsset = asset.copyWith(
        id: asset.id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : asset.id,
      );
      assets.add(_toJson(newAsset));
      _saveLocalAssets(assets);
      throw Exception(
        'Failed to add asset. cloud.isConfigured=${_cloud.isConfigured}. resp.data was null (FC returned empty body)',
      );
    }
    if (resp.isEmpty) {
      // FC 返回空 body（HTTP 200 但无内容）→ 将 asset 存入本地缓存，然后返回完整列表
      debugPrint(
        '[CloudAssetDataSource] addAsset: FC empty body, saving asset locally and returning fresh list.',
      );
      final assets = _loadLocalAssets();
      final newAsset = asset.copyWith(
        id: asset.id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : asset.id,
      );
      assets.add(_toJson(newAsset));
      _saveLocalAssets(assets);
      return newAsset;
    }
    debugPrint('[CloudAssetDataSource] addAsset: resp keys=${resp.keys.toList()}');
    // FC 返回 {'asset': {...}} 或 {'data': {'asset': {...}}}
    Map<String, dynamic>? assetData;
    if (resp.containsKey('asset')) {
      assetData = resp['asset'] as Map<String, dynamic>;
    } else if (resp['data'] != null) {
      assetData = (resp['data'] as Map)['asset'] as Map<String, dynamic>?;
    }
    if (assetData == null) throw Exception('Invalid response');
    return _fromJson(assetData);
  }

  @override
  Future<Asset> updateAsset(Asset asset) async {
    final existing = (await getAssets())
        .where((e) => e.id == asset.id)
        .cast<Asset?>()
        .firstWhere((e) => e != null, orElse: () => null);
    _assertUpdateAllowed(asset, existing);

    final phone = _phone;

    // 游客：仅更新本地
    if (phone == null || phone.isEmpty) {
      final syncedAsset = asset.copyWith(syncStatus: SyncStatus.synced);
      _upsertLocalAsset(syncedAsset);
      return syncedAsset;
    }

    if (phone == 'DemoAccount') {
      final assets = _loadDemoAssets();
      final idx = assets.indexWhere((e) => e['id'] == asset.id);
      if (idx < 0) throw Exception('Asset not found');
      assets[idx] = _toJson(asset);
      await _saveDemoAssets(assets);
      return asset.copyWith(syncStatus: SyncStatus.synced);
    }

    final syncedAsset = asset.copyWith(syncStatus: SyncStatus.synced);
    final resp = await _cloud.put('/assets/${asset.id}', body: _toJson(asset));

    if (resp == null || resp.isEmpty) {
      _upsertLocalAsset(syncedAsset);
      return syncedAsset;
    }

    // 兼容多种 FC 返回：
    // 1) {'asset': {...}}
    // 2) {'data': {'asset': {...}}}
    // 3) 直接返回资产对象 {...}
    // 4) {'assets': [...]} 返回完整列表
    Map<String, dynamic>? assetData;
    if (resp.containsKey('asset') && resp['asset'] is Map<String, dynamic>) {
      assetData = resp['asset'] as Map<String, dynamic>;
    } else if (resp['data'] is Map &&
        (resp['data'] as Map)['asset'] is Map<String, dynamic>) {
      assetData = (resp['data'] as Map)['asset'] as Map<String, dynamic>;
    } else if (resp.containsKey('id') &&
        resp.containsKey('name') &&
        resp.containsKey('type') &&
        resp.containsKey('balance')) {
      assetData = resp;
    } else if (resp['assets'] is List) {
      final assets = (resp['assets'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _saveLocalAssets(assets);
      final matched = assets
          .where((e) => e['id'] == asset.id)
          .cast<Map<String, dynamic>?>()
          .firstWhere((e) => e != null, orElse: () => null);
      if (matched != null) {
        return _fromJson(matched);
      }
      return syncedAsset;
    }

    if (assetData == null) {
      _upsertLocalAsset(syncedAsset);
      return syncedAsset;
    }

    final parsed = _fromJson(assetData);
    _upsertLocalAsset(parsed);
    return parsed;
  }

  @override
  Future<void> deleteAsset(String id) async {
    final phone = _phone;

    // 游客：仅删除本地
    if (phone == null || phone.isEmpty) {
      final assets = _loadLocalAssets()..removeWhere((e) => e['id'] == id);
      _saveLocalAssets(assets);
      return;
    }

    if (phone == 'DemoAccount') {
      final assets = _loadDemoAssets();
      assets.removeWhere((e) => e['id'] == id);
      await _saveDemoAssets(assets);
      return;
    }

    await _cloud.delete('/assets/$id');
  }
}
