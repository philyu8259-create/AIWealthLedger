import 'package:dartz/dartz.dart';
import 'package:get_it/get_it.dart';
import '../../../../app/app_flavor.dart';
import '../../../../services/app_profile_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/asset_repository.dart';
import '../datasources/i_asset_datasource.dart';

class AssetRepositoryImpl implements AssetRepository {
  final IAssetDataSource _dataSource;

  bool get _isIntl {
    if (GetIt.instance.isRegistered<AppProfileService>()) {
      return GetIt.instance<AppProfileService>().flavor.isIntl;
    }
    return AppFlavorX.current.isIntl;
  }

  String _message(String zh, String en) => _isIntl ? en : zh;

  AssetRepositoryImpl(this._dataSource);

  @override
  Future<Either<String, List<Asset>>> getAssets() async {
    try {
      final assets = await _dataSource.getAssets();
      return Right(assets);
    } catch (e) {
      return Left(_message('获取账户失败: $e', 'Failed to load assets: $e'));
    }
  }

  @override
  Future<Either<String, List<Asset>>> addAsset(Asset asset) async {
    try {
      await _dataSource.addAsset(asset);
      final assets = await _dataSource.getAssets();
      return Right(assets);
    } catch (e) {
      return Left(_message('添加账户失败: $e', 'Failed to add asset: $e'));
    }
  }

  @override
  Future<Either<String, Asset>> updateAsset(Asset asset) async {
    try {
      final result = await _dataSource.updateAsset(asset);
      return Right(result);
    } catch (e) {
      return Left(_message('更新账户失败: $e', 'Failed to update asset: $e'));
    }
  }

  @override
  Future<Either<String, void>> deleteAsset(String id) async {
    try {
      await _dataSource.deleteAsset(id);
      return const Right(null);
    } catch (e) {
      return Left(_message('删除账户失败: $e', 'Failed to delete asset: $e'));
    }
  }
}
