import '../../domain/entities/entities.dart';

/// 资产账户数据源接口（抽象层）
abstract class IAssetDataSource {
  Future<List<Asset>> getAssets();
  Future<Asset> addAsset(Asset asset);
  Future<Asset> updateAsset(Asset asset);
  Future<void> deleteAsset(String id);
}
